#include "LibreDWGCBridge.h"

#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dwg.h"
#include "bits.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef struct SKAffineTransform2D {
  double a;
  double b;
  double c;
  double d;
  double tx;
  double ty;
} SKAffineTransform2D;

typedef struct SKParseContext {
  SKCADParseResult *result;
  Dwg_Data *dwg;
  int capacity;
  BITCODE_RS textCodepageOverride;
  struct {
    int type;
    int count;
  } unsupportedTypes[16];
  int unsupportedTypeCount;
} SKParseContext;

typedef struct SKStrokeStyle {
  unsigned int rgb;
  double width;
} SKStrokeStyle;

#define SK_MAX_RECURSION_DEPTH 48

static void sk_set_error(SKCADParseResult *result, const char *fmt, ...) {
  if (!result) {
    return;
  }
  va_list args;
  va_start(args, fmt);
  vsnprintf(result->errorMessage, sizeof(result->errorMessage), fmt, args);
  va_end(args);
}

static SKAffineTransform2D sk_identity_transform(void) {
  SKAffineTransform2D t;
  t.a = 1.0;
  t.b = 0.0;
  t.c = 0.0;
  t.d = 1.0;
  t.tx = 0.0;
  t.ty = 0.0;
  return t;
}

static SKAffineTransform2D sk_compose_transform(SKAffineTransform2D parent,
                                                SKAffineTransform2D child) {
  SKAffineTransform2D out;
  out.a = parent.a * child.a + parent.b * child.c;
  out.b = parent.a * child.b + parent.b * child.d;
  out.c = parent.c * child.a + parent.d * child.c;
  out.d = parent.c * child.b + parent.d * child.d;
  out.tx = parent.a * child.tx + parent.b * child.ty + parent.tx;
  out.ty = parent.c * child.tx + parent.d * child.ty + parent.ty;
  return out;
}

static SKCADPoint sk_apply_point(SKAffineTransform2D t, double x, double y) {
  SKCADPoint out;
  out.x = t.a * x + t.b * y + t.tx;
  out.y = t.c * x + t.d * y + t.ty;
  return out;
}

static double sk_effective_scale(SKAffineTransform2D t) {
  const double sx = hypot(t.a, t.c);
  const double sy = hypot(t.b, t.d);
  if (!isfinite(sx) || !isfinite(sy) || sx <= 0.0 || sy <= 0.0) {
    return 1.0;
  }
  return (sx + sy) * 0.5;
}

static double sk_effective_rotation(SKAffineTransform2D t) {
  return atan2(t.c, t.a);
}

static bool sk_ensure_capacity(SKParseContext *ctx, int extraCount) {
  if (!ctx || !ctx->result || extraCount <= 0) {
    return false;
  }
  const int required = ctx->result->primitiveCount + extraCount;
  if (required <= ctx->capacity) {
    return true;
  }

  int nextCapacity = ctx->capacity > 0 ? ctx->capacity : 256;
  while (nextCapacity < required) {
    if (nextCapacity > 1 << 28) {
      sk_set_error(ctx->result, "DWG 实体数量过大，无法分配内存。");
      return false;
    }
    nextCapacity <<= 1;
  }

  SKCADPrimitive *next = (SKCADPrimitive *)realloc(
      ctx->result->primitives, (size_t)nextCapacity * sizeof(SKCADPrimitive));
  if (!next) {
    sk_set_error(ctx->result, "DWG 预览内存分配失败。");
    return false;
  }

  memset(next + ctx->capacity, 0,
         (size_t)(nextCapacity - ctx->capacity) * sizeof(SKCADPrimitive));
  ctx->result->primitives = next;
  ctx->capacity = nextCapacity;
  return true;
}

static char *sk_strdup_safe(const char *text) {
  if (!text || !text[0]) {
    return NULL;
  }
  const size_t len = strlen(text);
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    return NULL;
  }
  memcpy(copy, text, len + 1);
  return copy;
}

static bool sk_is_valid_utf8(const char *text) {
  if (!text) {
    return false;
  }
  const unsigned char *bytes = (const unsigned char *)text;
  while (*bytes) {
    if (*bytes <= 0x7F) {
      bytes += 1;
      continue;
    }
    if ((*bytes & 0xE0) == 0xC0) {
      if (!bytes[1]) {
        return false;
      }
      if ((bytes[1] & 0xC0) != 0x80 || (*bytes == 0xC0 || *bytes == 0xC1)) {
        return false;
      }
      bytes += 2;
      continue;
    }
    if ((*bytes & 0xF0) == 0xE0) {
      if (!bytes[1] || !bytes[2]) {
        return false;
      }
      if ((bytes[1] & 0xC0) != 0x80 || (bytes[2] & 0xC0) != 0x80) {
        return false;
      }
      if (*bytes == 0xE0 && bytes[1] < 0xA0) {
        return false;
      }
      bytes += 3;
      continue;
    }
    if ((*bytes & 0xF8) == 0xF0) {
      if (!bytes[1] || !bytes[2] || !bytes[3]) {
        return false;
      }
      if ((bytes[1] & 0xC0) != 0x80 || (bytes[2] & 0xC0) != 0x80 ||
          (bytes[3] & 0xC0) != 0x80) {
        return false;
      }
      if (*bytes > 0xF4 || (*bytes == 0xF0 && bytes[1] < 0x90) ||
          (*bytes == 0xF4 && bytes[1] > 0x8F)) {
        return false;
      }
      bytes += 4;
      continue;
    }
    return false;
  }
  return true;
}

static char *sk_copy_converted_utf8(const char *source, BITCODE_RS codepage) {
  char *converted = bit_TV_to_utf8(source, codepage);
  if (!converted || !converted[0]) {
    if (converted && converted != source) {
      free(converted);
    }
    return NULL;
  }
  const char *candidate = converted;
  if (!sk_is_valid_utf8(candidate)) {
    if (converted != source) {
      free(converted);
    }
    return NULL;
  }
  char *copy = sk_strdup_safe(candidate);
  if (converted != source) {
    free(converted);
  }
  return copy;
}

static char *sk_utf8_copy(const char *text, BITCODE_RS codepage) {
  if (!text || !text[0]) {
    return NULL;
  }
  if (sk_is_valid_utf8(text)) {
    return sk_strdup_safe(text);
  }

  // DWG codepage sometimes comes as 0 in the header for legacy drawings.
  // Try header codepage first, then common East-Asia fallbacks.
  const BITCODE_RS fallbackCodepages[] = { 936, 950, 932, 65001 };
  if (codepage > 0) {
    char *copy = sk_copy_converted_utf8(text, codepage);
    if (copy) {
      return copy;
    }
  }
  for (size_t index = 0; index < sizeof(fallbackCodepages) / sizeof(fallbackCodepages[0]); index++) {
    const BITCODE_RS fallback = fallbackCodepages[index];
    if (fallback == codepage) {
      continue;
    }
    char *copy = sk_copy_converted_utf8(text, fallback);
    if (copy) {
      return copy;
    }
  }

  // Final fallback to keep UI stable even when source bytes are unknown.
  char *lossy = sk_strdup_safe(text);
  if (!lossy) {
    return NULL;
  }
  unsigned char *bytes = (unsigned char *)lossy;
  while (*bytes) {
    if (*bytes >= 0x80) {
      *bytes = '?';
    }
    bytes += 1;
  }
  return lossy;
}

static unsigned int sk_rgb_from_color(const Dwg_Color *color) {
  if (!color) {
    return 0;
  }
  if (color->method == DWG_COLOR_METHOD_TRUECOLOR ||
      color->method == DWG_COLOR_METHOD_FGCOLOR) {
    const unsigned int rgb = (unsigned int)(color->rgb & 0x00FFFFFFu);
    if (rgb != 0) {
      return rgb;
    }
  }
  if (color->index > 0 && color->index < 256) {
    const BITCODE_BL rgb = dwg_rgb_palette_index((BITCODE_BS)color->index);
    return (unsigned int)(rgb & 0x00FFFFFFu);
  }
  if ((color->rgb & 0x00FFFFFFu) != 0) {
    return (unsigned int)(color->rgb & 0x00FFFFFFu);
  }
  return 0;
}

static unsigned int sk_default_rgb(void) {
  return 0x2A2A2Au;
}

static double sk_default_stroke_width(void) {
  return 1.0;
}

static double sk_stroke_width_from_linewt(BITCODE_RC linewt,
                                          const Dwg_Object_LAYER *layer) {
  int lw100th = dxf_cvt_lweight((BITCODE_BSd)linewt);
  if ((lw100th == -1 || lw100th == -2 || lw100th == -3) && layer) {
    lw100th = dxf_cvt_lweight((BITCODE_BSd)layer->linewt);
  }
  if (lw100th <= 0) {
    return sk_default_stroke_width();
  }
  const double mm = (double)lw100th / 100.0;
  if (!isfinite(mm) || mm <= 0.0) {
    return sk_default_stroke_width();
  }
  // 1pt = 0.3527mm
  double points = mm / 0.352777778;
  if (!isfinite(points) || points <= 0.0) {
    return sk_default_stroke_width();
  }
  if (points < 0.45) {
    points = 0.45;
  } else if (points > 4.0) {
    points = 4.0;
  }
  return points;
}

static SKStrokeStyle sk_style_from_entity(const Dwg_Object_Entity *entity) {
  SKStrokeStyle style;
  style.rgb = sk_default_rgb();
  style.width = sk_default_stroke_width();
  if (!entity) {
    return style;
  }

  const Dwg_Object_LAYER *layer = dwg_get_entity_layer(entity);
  const Dwg_Color *source = &entity->color;
  const bool byLayer = source->method == DWG_COLOR_METHOD_BYLAYER ||
                       source->index == 256 ||
                       source->method == DWG_COLOR_METHOD_VOID;
  if (byLayer && layer) {
    source = &layer->color;
  }

  unsigned int rgb = sk_rgb_from_color(source);
  if (rgb == 0 && layer && source != &layer->color) {
    rgb = sk_rgb_from_color(&layer->color);
  }
  style.rgb = rgb != 0 ? rgb : sk_default_rgb();
  style.width = sk_stroke_width_from_linewt(entity->linewt, layer);
  return style;
}

static const char *sk_layer_name_from_entity(const Dwg_Object_Entity *entity) {
  if (!entity) {
    return "0";
  }
  const Dwg_Object_LAYER *layer = dwg_get_entity_layer(entity);
  if (!layer || !layer->name || !layer->name[0]) {
    return "0";
  }
  return layer->name;
}

static const char *sk_entity_type_name(int type) {
  switch (type) {
  case DWG_TYPE_SPLINE:
    return "SPLINE";
  case DWG_TYPE_HATCH:
    return "HATCH";
  case DWG_TYPE_SOLID:
    return "SOLID";
  case DWG_TYPE_TRACE:
    return "TRACE";
  case DWG_TYPE_POINT:
    return "POINT";
  case DWG_TYPE_MLINE:
    return "MLINE";
  case DWG_TYPE_ELLIPSE:
    return "ELLIPSE";
  case DWG_TYPE_LEADER:
    return "LEADER";
  case DWG_TYPE_MULTILEADER:
    return "MULTILEADER";
  case DWG_TYPE_IMAGE:
    return "IMAGE";
  case DWG_TYPE_WIPEOUT:
    return "WIPEOUT";
  case DWG_TYPE_POLYLINE_MESH:
    return "POLYLINE_MESH";
  case DWG_TYPE_POLYLINE_PFACE:
    return "POLYLINE_PFACE";
  case DWG_TYPE__3DFACE:
    return "3DFACE";
  case DWG_TYPE__3DSOLID:
    return "3DSOLID";
  default:
    return "UNKNOWN";
  }
}

static void sk_track_unsupported(SKParseContext *ctx, int type) {
  if (!ctx) {
    return;
  }
  for (int index = 0; index < ctx->unsupportedTypeCount; index++) {
    if (ctx->unsupportedTypes[index].type == type) {
      ctx->unsupportedTypes[index].count += 1;
      return;
    }
  }
  if (ctx->unsupportedTypeCount < (int)(sizeof(ctx->unsupportedTypes) / sizeof(ctx->unsupportedTypes[0]))) {
    ctx->unsupportedTypes[ctx->unsupportedTypeCount].type = type;
    ctx->unsupportedTypes[ctx->unsupportedTypeCount].count = 1;
    ctx->unsupportedTypeCount += 1;
  }
}

static bool sk_append_line(SKParseContext *ctx, SKAffineTransform2D transform,
                           double x1, double y1, double x2, double y2,
                           SKStrokeStyle style, const char *layerName) {
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = SKCADPrimitiveLine;
  primitive->start = sk_apply_point(transform, x1, y1);
  primitive->end = sk_apply_point(transform, x2, y2);
  primitive->layerName = sk_strdup_safe(layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  return true;
}

static bool sk_append_arc(SKParseContext *ctx, SKAffineTransform2D transform,
                          double cx, double cy, double radius, double startAngle,
                          double endAngle, SKStrokeStyle style,
                          const char *layerName) {
  if (!isfinite(radius) || radius <= 0.0) {
    return true;
  }
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = SKCADPrimitiveArc;
  primitive->center = sk_apply_point(transform, cx, cy);
  primitive->radius = radius * sk_effective_scale(transform);
  primitive->startAngle = startAngle + sk_effective_rotation(transform);
  primitive->endAngle = endAngle + sk_effective_rotation(transform);
  primitive->layerName = sk_strdup_safe(layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  return true;
}

static bool sk_append_circle(SKParseContext *ctx, SKAffineTransform2D transform,
                             double cx, double cy, double radius,
                             SKStrokeStyle style, const char *layerName) {
  if (!isfinite(radius) || radius <= 0.0) {
    return true;
  }
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = SKCADPrimitiveCircle;
  primitive->center = sk_apply_point(transform, cx, cy);
  primitive->radius = radius * sk_effective_scale(transform);
  primitive->layerName = sk_strdup_safe(layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  return true;
}

static bool sk_append_text(SKParseContext *ctx, SKAffineTransform2D transform,
                           double x, double y, double height, double rotation,
                           const char *text, SKStrokeStyle style,
                           const char *layerName) {
  if (!text || !text[0]) {
    return true;
  }
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = SKCADPrimitiveText;
  primitive->start = sk_apply_point(transform, x, y);
  primitive->textHeight =
      (height > 0.0 && isfinite(height)) ? height * sk_effective_scale(transform)
                                         : 2.0;
  primitive->textRotation = rotation + sk_effective_rotation(transform);
  primitive->layerName = sk_strdup_safe(layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  BITCODE_RS codepage = 0;
  if (ctx) {
    codepage = ctx->textCodepageOverride > 0
                   ? ctx->textCodepageOverride
                   : (ctx->dwg ? ctx->dwg->header.codepage : 0);
  }
  primitive->text = sk_utf8_copy(text, codepage);
  if (!primitive->text) {
    primitive->text = NULL;
  }
  return true;
}

static bool sk_append_lwpolyline(SKParseContext *ctx,
                                 const Dwg_Entity_LWPOLYLINE *lwpolyline,
                                 SKAffineTransform2D transform,
                                 SKStrokeStyle style,
                                 const char *layerName) {
  if (!lwpolyline || lwpolyline->num_points < 2 || !lwpolyline->points) {
    return true;
  }
  for (BITCODE_BL index = 1; index < lwpolyline->num_points; index++) {
    const BITCODE_2RD p0 = lwpolyline->points[index - 1];
    const BITCODE_2RD p1 = lwpolyline->points[index];
    if (!sk_append_line(ctx, transform, p0.x, p0.y, p1.x, p1.y, style, layerName)) {
      return false;
    }
  }
  if ((lwpolyline->flag & 512) == 512 && lwpolyline->num_points > 2) {
    const BITCODE_2RD first = lwpolyline->points[0];
    const BITCODE_2RD last = lwpolyline->points[lwpolyline->num_points - 1];
    if (!sk_append_line(ctx, transform, last.x, last.y, first.x, first.y, style, layerName)) {
      return false;
    }
  }
  return true;
}

static bool sk_append_polyline_from_subentities(SKParseContext *ctx,
                                                const Dwg_Object *polylineObject,
                                                SKAffineTransform2D transform,
                                                bool closed,
                                                SKStrokeStyle style,
                                                const char *layerName) {
  if (!polylineObject) {
    return true;
  }
  Dwg_Object *subentity = get_first_owned_subentity(polylineObject);
  bool hasPoint = false;
  double firstX = 0.0;
  double firstY = 0.0;
  double lastX = 0.0;
  double lastY = 0.0;

  while (subentity) {
    bool didAppendPoint = false;
    double x = 0.0;
    double y = 0.0;

    switch (subentity->fixedtype) {
    case DWG_TYPE_VERTEX_2D: {
      const Dwg_Entity_VERTEX_2D *vertex = subentity->tio.entity->tio.VERTEX_2D;
      if (vertex) {
        x = vertex->point.x;
        y = vertex->point.y;
        didAppendPoint = true;
      }
      break;
    }
    case DWG_TYPE_VERTEX_3D:
    case DWG_TYPE_VERTEX_MESH:
    case DWG_TYPE_VERTEX_PFACE: {
      const Dwg_Entity_VERTEX_3D *vertex = subentity->tio.entity->tio.VERTEX_3D;
      if (vertex) {
        x = vertex->point.x;
        y = vertex->point.y;
        didAppendPoint = true;
      }
      break;
    }
    case DWG_TYPE_SEQEND:
      subentity = NULL;
      continue;
    default:
      break;
    }

    if (didAppendPoint) {
      if (hasPoint) {
        if (!sk_append_line(ctx, transform, lastX, lastY, x, y, style, layerName)) {
          return false;
        }
      } else {
        firstX = x;
        firstY = y;
      }
      lastX = x;
      lastY = y;
      hasPoint = true;
    }

    Dwg_Object *next = get_next_owned_subentity(polylineObject, subentity);
    if (!next || next == subentity) {
      break;
    }
    subentity = next;
  }

  if (closed && hasPoint && (fabs(firstX - lastX) > 1e-9 || fabs(firstY - lastY) > 1e-9)) {
    if (!sk_append_line(ctx, transform, lastX, lastY, firstX, firstY, style, layerName)) {
      return false;
    }
  }
  return true;
}

static bool sk_append_ellipse(SKParseContext *ctx, const Dwg_Entity_ELLIPSE *ellipse,
                              SKAffineTransform2D transform,
                              SKStrokeStyle style,
                              const char *layerName) {
  if (!ellipse) {
    return true;
  }
  const double majorX = ellipse->sm_axis.x;
  const double majorY = ellipse->sm_axis.y;
  const double majorRadius = hypot(majorX, majorY);
  const double ratio = ellipse->axis_ratio;
  if (!isfinite(majorRadius) || majorRadius <= 0.0 || !isfinite(ratio) || ratio <= 0.0) {
    return true;
  }

  double startAngle = ellipse->start_angle;
  double endAngle = ellipse->end_angle;
  if (!isfinite(startAngle) || !isfinite(endAngle)) {
    startAngle = 0.0;
    endAngle = M_PI * 2.0;
  }

  while (endAngle < startAngle) {
    endAngle += M_PI * 2.0;
  }
  const double span = fmax(endAngle - startAngle, 0.0);
  const int segments = (int)fmax(24.0, ceil(span / (M_PI / 24.0)));
  const double majorAngle = atan2(majorY, majorX);
  const double minorRadius = majorRadius * ratio;

  double prevX = 0.0;
  double prevY = 0.0;
  bool hasPrev = false;
  for (int index = 0; index <= segments; index++) {
    const double t = (double)index / (double)segments;
    const double theta = startAngle + span * t;
    const double localX = majorRadius * cos(theta);
    const double localY = minorRadius * sin(theta);
    const double worldX = ellipse->center.x + localX * cos(majorAngle) - localY * sin(majorAngle);
    const double worldY = ellipse->center.y + localX * sin(majorAngle) + localY * cos(majorAngle);
    if (hasPrev) {
      if (!sk_append_line(ctx, transform, prevX, prevY, worldX, worldY, style, layerName)) {
        return false;
      }
    }
    prevX = worldX;
    prevY = worldY;
    hasPrev = true;
  }
  return true;
}

static bool sk_append_line_if_valid(SKParseContext *ctx, SKAffineTransform2D transform,
                                    double x1, double y1, double x2, double y2,
                                    SKStrokeStyle style, const char *layerName) {
  if (!isfinite(x1) || !isfinite(y1) || !isfinite(x2) || !isfinite(y2)) {
    return true;
  }
  if (fabs(x1 - x2) <= 1e-9 && fabs(y1 - y2) <= 1e-9) {
    return true;
  }
  return sk_append_line(ctx, transform, x1, y1, x2, y2, style, layerName);
}

static bool sk_append_attrib_like_text(SKParseContext *ctx, SKAffineTransform2D transform,
                                       double x, double y, double height, double rotation,
                                       const char *textValue, SKStrokeStyle style,
                                       const char *layerName) {
  if (!textValue || !textValue[0]) {
    return true;
  }
  return sk_append_text(ctx, transform, x, y, height, rotation, textValue, style, layerName);
}

static bool sk_append_dimension_text(SKParseContext *ctx, SKAffineTransform2D transform,
                                     double textX, double textY, double textRotation,
                                     const char *userText, double measurement,
                                     SKStrokeStyle style, const char *layerName) {
  char autoText[96];
  const char *displayText = userText;
  if (!displayText || !displayText[0] || strcmp(displayText, "<>") == 0) {
    if (!isfinite(measurement) || measurement <= 0.0) {
      return true;
    }
    snprintf(autoText, sizeof(autoText), "%.3f", measurement);
    displayText = autoText;
  }
  return sk_append_text(ctx, transform, textX, textY, 2.2, textRotation, displayText, style, layerName);
}

static bool sk_append_solid_outline(SKParseContext *ctx, SKAffineTransform2D transform,
                                    double x1, double y1, double x2, double y2,
                                    double x3, double y3, double x4, double y4,
                                    SKStrokeStyle style, const char *layerName) {
  if (!sk_append_line_if_valid(ctx, transform, x1, y1, x2, y2, style, layerName)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, x2, y2, x3, y3, style, layerName)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, x3, y3, x4, y4, style, layerName)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, x4, y4, x1, y1, style, layerName)) {
    return false;
  }
  return true;
}

static bool sk_append_dimension_linear_like(SKParseContext *ctx, SKAffineTransform2D transform,
                                            const Dwg_Entity_DIMENSION_LINEAR *dim,
                                            SKStrokeStyle style, const char *layerName) {
  if (!dim) {
    return true;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline1_pt.x, dim->xline1_pt.y,
                               dim->xline2_pt.x, dim->xline2_pt.y, style, layerName)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline1_pt.x, dim->xline1_pt.y,
                               dim->def_pt.x, dim->def_pt.y, style, layerName)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline2_pt.x, dim->xline2_pt.y,
                               dim->def_pt.x, dim->def_pt.y, style, layerName)) {
    return false;
  }
  return sk_append_dimension_text(ctx, transform, dim->text_midpt.x, dim->text_midpt.y,
                                  dim->text_rotation, dim->user_text,
                                  dim->act_measurement, style, layerName);
}

static bool sk_append_dimension_aligned_like(SKParseContext *ctx, SKAffineTransform2D transform,
                                             const Dwg_Entity_DIMENSION_ALIGNED *dim,
                                             SKStrokeStyle style, const char *layerName) {
  if (!dim) {
    return true;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline1_pt.x, dim->xline1_pt.y,
                               dim->xline2_pt.x, dim->xline2_pt.y, style, layerName)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline1_pt.x, dim->xline1_pt.y,
                               dim->def_pt.x, dim->def_pt.y, style, layerName)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline2_pt.x, dim->xline2_pt.y,
                               dim->def_pt.x, dim->def_pt.y, style, layerName)) {
    return false;
  }
  return sk_append_dimension_text(ctx, transform, dim->text_midpt.x, dim->text_midpt.y,
                                  dim->text_rotation, dim->user_text,
                                  dim->act_measurement, style, layerName);
}

static bool sk_append_hatch_arc_segment(SKParseContext *ctx, SKAffineTransform2D transform,
                                        double cx, double cy, double radius,
                                        double startAngle, double endAngle, bool isCCW,
                                        SKStrokeStyle style, const char *layerName) {
  if (!isfinite(radius) || radius <= 0.0) {
    return true;
  }
  if (!isCCW) {
    const double tmp = startAngle;
    startAngle = endAngle;
    endAngle = tmp;
  }
  return sk_append_arc(ctx, transform, cx, cy, radius, startAngle, endAngle, style, layerName);
}

static bool sk_append_hatch_ellipse_segment(SKParseContext *ctx, SKAffineTransform2D transform,
                                            double cx, double cy, double majorX, double majorY,
                                            double minorMajorRatio, double startAngle,
                                            double endAngle, bool isCCW,
                                            SKStrokeStyle style, const char *layerName) {
  const double majorRadius = hypot(majorX, majorY);
  if (!isfinite(majorRadius) || majorRadius <= 0.0 || !isfinite(minorMajorRatio) ||
      minorMajorRatio <= 0.0) {
    return true;
  }
  if (!isCCW) {
    const double tmp = startAngle;
    startAngle = endAngle;
    endAngle = tmp;
  }
  while (endAngle < startAngle) {
    endAngle += M_PI * 2.0;
  }
  const double span = fmax(endAngle - startAngle, 0.0);
  const int segments = (int)fmax(16.0, ceil(span / (M_PI / 24.0)));
  const double majorAngle = atan2(majorY, majorX);
  const double minorRadius = majorRadius * minorMajorRatio;

  double prevX = 0.0;
  double prevY = 0.0;
  bool hasPrev = false;
  for (int index = 0; index <= segments; index++) {
    const double t = (double)index / (double)segments;
    const double theta = startAngle + span * t;
    const double localX = majorRadius * cos(theta);
    const double localY = minorRadius * sin(theta);
    const double worldX = cx + localX * cos(majorAngle) - localY * sin(majorAngle);
    const double worldY = cy + localX * sin(majorAngle) + localY * cos(majorAngle);
    if (hasPrev) {
      if (!sk_append_line_if_valid(ctx, transform, prevX, prevY, worldX, worldY, style, layerName)) {
        return false;
      }
    }
    prevX = worldX;
    prevY = worldY;
    hasPrev = true;
  }
  return true;
}

static bool sk_append_bulge_arc(SKParseContext *ctx, SKAffineTransform2D transform,
                                double x1, double y1, double x2, double y2, double bulge,
                                SKStrokeStyle style, const char *layerName) {
  if (!isfinite(bulge) || fabs(bulge) <= 1e-9) {
    return sk_append_line_if_valid(ctx, transform, x1, y1, x2, y2, style, layerName);
  }
  const double dx = x2 - x1;
  const double dy = y2 - y1;
  const double chord = hypot(dx, dy);
  if (!isfinite(chord) || chord <= 1e-9) {
    return true;
  }
  const double alpha = atan2(dy, dx);
  const double offsetAngle = alpha + ((M_PI / 2.0) - (2.0 * atan(bulge)));
  const double centerDistance = (chord * (1.0 + bulge * bulge)) / (4.0 * bulge);
  const double cx = x1 + cos(offsetAngle) * centerDistance;
  const double cy = y1 + sin(offsetAngle) * centerDistance;
  const double radius = fabs((chord * (1.0 + bulge * bulge)) / (4.0 * bulge));
  double startAngle = atan2(y1 - cy, x1 - cx);
  double endAngle = atan2(y2 - cy, x2 - cx);
  if (bulge < 0.0) {
    const double tmp = startAngle;
    startAngle = endAngle;
    endAngle = tmp;
  }
  return sk_append_arc(ctx, transform, cx, cy, radius, startAngle, endAngle, style, layerName);
}

static bool sk_append_hatch_entity(SKParseContext *ctx, const Dwg_Entity_HATCH *hatch,
                                   SKAffineTransform2D transform, SKStrokeStyle style,
                                   const char *layerName) {
  if (!hatch || hatch->num_paths <= 0 || !hatch->paths) {
    return true;
  }
  for (BITCODE_BL pathIndex = 0; pathIndex < hatch->num_paths; pathIndex++) {
    const Dwg_HATCH_Path *path = &hatch->paths[pathIndex];
    if (!path) {
      continue;
    }
    const bool isPolyline = (path->flag & 2) == 2;
    if (isPolyline) {
      const BITCODE_BL count = path->num_segs_or_paths;
      if (!path->polyline_paths || count < 2) {
        continue;
      }
      const BITCODE_BL segmentCount = path->closed ? count : count - 1;
      for (BITCODE_BL index = 0; index < segmentCount; index++) {
        const BITCODE_BL next = (index + 1) % count;
        const Dwg_HATCH_PolylinePath *p0 = &path->polyline_paths[index];
        const Dwg_HATCH_PolylinePath *p1 = &path->polyline_paths[next];
        const double bulge = path->bulges_present ? p0->bulge : 0.0;
        if (!sk_append_bulge_arc(ctx, transform, p0->point.x, p0->point.y,
                                 p1->point.x, p1->point.y, bulge, style, layerName)) {
          return false;
        }
      }
      continue;
    }

    const BITCODE_BL segCount = path->num_segs_or_paths;
    if (!path->segs || segCount <= 0) {
      continue;
    }
    for (BITCODE_BL segIndex = 0; segIndex < segCount; segIndex++) {
      const Dwg_HATCH_PathSeg *seg = &path->segs[segIndex];
      if (!seg) {
        continue;
      }
      switch (seg->curve_type) {
      case 1:
        if (!sk_append_line_if_valid(ctx, transform, seg->first_endpoint.x, seg->first_endpoint.y,
                                     seg->second_endpoint.x, seg->second_endpoint.y, style, layerName)) {
          return false;
        }
        break;
      case 2:
        if (!sk_append_hatch_arc_segment(ctx, transform, seg->center.x, seg->center.y, seg->radius,
                                         seg->start_angle, seg->end_angle, seg->is_ccw != 0,
                                         style, layerName)) {
          return false;
        }
        break;
      case 3:
        if (!sk_append_hatch_ellipse_segment(ctx, transform, seg->center.x, seg->center.y,
                                             seg->endpoint.x, seg->endpoint.y,
                                             seg->minor_major_ratio, seg->start_angle,
                                             seg->end_angle, seg->is_ccw != 0,
                                             style, layerName)) {
          return false;
        }
        break;
      case 4:
        if (seg->fitpts && seg->num_fitpts > 1) {
          for (BITCODE_BL fitIndex = 1; fitIndex < seg->num_fitpts; fitIndex++) {
            const BITCODE_2RD p0 = seg->fitpts[fitIndex - 1];
            const BITCODE_2RD p1 = seg->fitpts[fitIndex];
            if (!sk_append_line_if_valid(ctx, transform, p0.x, p0.y, p1.x, p1.y, style, layerName)) {
              return false;
            }
          }
        } else if (seg->control_points && seg->num_control_points > 1) {
          for (BITCODE_BL cpIndex = 1; cpIndex < seg->num_control_points; cpIndex++) {
            const BITCODE_2RD p0 = seg->control_points[cpIndex - 1].point;
            const BITCODE_2RD p1 = seg->control_points[cpIndex].point;
            if (!sk_append_line_if_valid(ctx, transform, p0.x, p0.y, p1.x, p1.y, style, layerName)) {
              return false;
            }
          }
        }
        break;
      default:
        break;
      }
    }
  }
  return true;
}

static bool sk_append_leader_entity(SKParseContext *ctx, const Dwg_Entity_LEADER *leader,
                                    SKAffineTransform2D transform, SKStrokeStyle style,
                                    const char *layerName) {
  if (!leader || !leader->points || leader->num_points <= 1) {
    return true;
  }
  for (BITCODE_BL index = 1; index < leader->num_points; index++) {
    const BITCODE_3DPOINT p0 = leader->points[index - 1];
    const BITCODE_3DPOINT p1 = leader->points[index];
    if (!sk_append_line_if_valid(ctx, transform, p0.x, p0.y, p1.x, p1.y, style, layerName)) {
      return false;
    }
  }
  return true;
}

static bool sk_append_multileader_entity(SKParseContext *ctx, const Dwg_Entity_MULTILEADER *leader,
                                         SKAffineTransform2D transform, SKStrokeStyle style,
                                         const char *layerName) {
  if (!leader) {
    return true;
  }
  if (leader->ctx.leaders && leader->ctx.num_leaders > 0) {
    for (BITCODE_BL nodeIndex = 0; nodeIndex < leader->ctx.num_leaders; nodeIndex++) {
      const Dwg_LEADER_Node *node = &leader->ctx.leaders[nodeIndex];
      if (!node || !node->lines || node->num_lines <= 0) {
        continue;
      }
      for (BITCODE_BL lineIndex = 0; lineIndex < node->num_lines; lineIndex++) {
        const Dwg_LEADER_Line *line = &node->lines[lineIndex];
        if (!line || !line->points || line->num_points <= 1) {
          continue;
        }
        for (BITCODE_BL pointIndex = 1; pointIndex < line->num_points; pointIndex++) {
          const BITCODE_3DPOINT p0 = line->points[pointIndex - 1];
          const BITCODE_3DPOINT p1 = line->points[pointIndex];
          if (!sk_append_line_if_valid(ctx, transform, p0.x, p0.y, p1.x, p1.y, style, layerName)) {
            return false;
          }
        }
      }
    }
  }
  if (leader->ctx.has_content_txt) {
    const Dwg_MLEADER_Content_MText *txt = &leader->ctx.content.txt;
    if (!sk_append_text(ctx, transform, txt->location.x, txt->location.y,
                        leader->ctx.text_height > 0.0 ? leader->ctx.text_height : 2.2,
                        txt->rotation, txt->default_text, style, layerName)) {
      return false;
    }
  }
  return true;
}

static bool sk_append_image_like_entity(SKParseContext *ctx, const BITCODE_3BD pt0,
                                        const BITCODE_3BD uvec, const BITCODE_3BD vvec,
                                        const BITCODE_2RD image_size,
                                        BITCODE_BL num_clip_verts, BITCODE_2RD *clip_verts,
                                        SKAffineTransform2D transform, SKStrokeStyle style,
                                        const char *layerName) {
  if (num_clip_verts > 1 && clip_verts) {
    for (BITCODE_BL index = 0; index < num_clip_verts; index++) {
      const BITCODE_BL next = (index + 1) % num_clip_verts;
      const BITCODE_2RD p0c = clip_verts[index];
      const BITCODE_2RD p1c = clip_verts[next];
      const double x0 = pt0.x + uvec.x * p0c.x + vvec.x * p0c.y;
      const double y0 = pt0.y + uvec.y * p0c.x + vvec.y * p0c.y;
      const double x1 = pt0.x + uvec.x * p1c.x + vvec.x * p1c.y;
      const double y1 = pt0.y + uvec.y * p1c.x + vvec.y * p1c.y;
      if (!sk_append_line_if_valid(ctx, transform, x0, y0, x1, y1, style, layerName)) {
        return false;
      }
    }
    return true;
  }

  const double width = image_size.x;
  const double height = image_size.y;
  const double ax = pt0.x;
  const double ay = pt0.y;
  const double bx = pt0.x + uvec.x * width;
  const double by = pt0.y + uvec.y * width;
  const double dx = pt0.x + vvec.x * height;
  const double dy = pt0.y + vvec.y * height;
  const double cx = bx + (dx - ax);
  const double cy = by + (dy - ay);
  return sk_append_solid_outline(ctx, transform, ax, ay, bx, by, cx, cy, dx, dy, style, layerName);
}

static SKAffineTransform2D sk_insert_transform(double tx, double ty, double sx,
                                               double sy, double rotation) {
  if (!isfinite(sx) || fabs(sx) < 1e-9) {
    sx = 1.0;
  }
  if (!isfinite(sy) || fabs(sy) < 1e-9) {
    sy = 1.0;
  }
  if (!isfinite(rotation)) {
    rotation = 0.0;
  }

  const double c = cos(rotation);
  const double s = sin(rotation);
  SKAffineTransform2D out;
  out.a = c * sx;
  out.b = -s * sy;
  out.c = s * sx;
  out.d = c * sy;
  out.tx = tx;
  out.ty = ty;
  return out;
}

static bool sk_is_in_stack(const Dwg_Object *object, const Dwg_Object **stack,
                           int stackCount) {
  if (!object || !stack || stackCount <= 0) {
    return false;
  }
  for (int index = 0; index < stackCount; index++) {
    if (stack[index] == object) {
      return true;
    }
  }
  return false;
}

static bool sk_parse_entity_object(SKParseContext *ctx, const Dwg_Object *object,
                                   SKAffineTransform2D transform,
                                   const Dwg_Object **stack, int stackCount);

static bool sk_parse_block_entities(SKParseContext *ctx,
                                    const Dwg_Object *blockHeaderObject,
                                    SKAffineTransform2D transform,
                                    const Dwg_Object **stack, int stackCount) {
  if (!ctx || !blockHeaderObject ||
      blockHeaderObject->fixedtype != DWG_TYPE_BLOCK_HEADER) {
    return true;
  }

  if (sk_is_in_stack(blockHeaderObject, stack, stackCount)) {
    ctx->result->unsupportedEntityCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_INSERT);
    return true;
  }

  if (stackCount >= SK_MAX_RECURSION_DEPTH) {
    sk_set_error(ctx->result, "DWG 块引用层级过深，已停止递归展开。");
    return false;
  }

  const Dwg_Object *nextStack[SK_MAX_RECURSION_DEPTH];
  for (int index = 0; index < stackCount; index++) {
    nextStack[index] = stack[index];
  }
  nextStack[stackCount] = blockHeaderObject;

  Dwg_Object *entity = get_first_owned_entity(blockHeaderObject);
  while (entity) {
    if (!sk_parse_entity_object(ctx, entity, transform, nextStack,
                                stackCount + 1)) {
      return false;
    }
    entity = get_next_owned_entity(blockHeaderObject, entity);
  }
  return true;
}

static bool sk_parse_insert_entity(SKParseContext *ctx,
                                   const Dwg_Entity_INSERT *insertEntity,
                                   SKAffineTransform2D transform,
                                   const Dwg_Object **stack, int stackCount) {
  if (!insertEntity || !insertEntity->block_header) {
    ctx->result->unsupportedEntityCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_INSERT);
    return true;
  }

  Dwg_Object *blockHeaderObject =
      insertEntity->block_header->obj
          ? insertEntity->block_header->obj
          : dwg_ref_object(ctx->dwg, insertEntity->block_header);
  if (!blockHeaderObject || blockHeaderObject->fixedtype != DWG_TYPE_BLOCK_HEADER) {
    ctx->result->unsupportedEntityCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_INSERT);
    return true;
  }

  const double sx = insertEntity->scale.x;
  const double sy = insertEntity->scale.y;
  const SKAffineTransform2D local = sk_insert_transform(
      insertEntity->ins_pt.x, insertEntity->ins_pt.y, sx, sy,
      insertEntity->rotation);
  const SKAffineTransform2D composed = sk_compose_transform(transform, local);

  return sk_parse_block_entities(ctx, blockHeaderObject, composed, stack,
                                 stackCount);
}

static bool sk_parse_minsert_entity(SKParseContext *ctx,
                                    const Dwg_Entity_MINSERT *insertEntity,
                                    SKAffineTransform2D transform,
                                    const Dwg_Object **stack, int stackCount) {
  if (!insertEntity || !insertEntity->block_header) {
    ctx->result->unsupportedEntityCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_MINSERT);
    return true;
  }

  Dwg_Object *blockHeaderObject =
      insertEntity->block_header->obj
          ? insertEntity->block_header->obj
          : dwg_ref_object(ctx->dwg, insertEntity->block_header);
  if (!blockHeaderObject || blockHeaderObject->fixedtype != DWG_TYPE_BLOCK_HEADER) {
    ctx->result->unsupportedEntityCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_MINSERT);
    return true;
  }

  int rows = (int)insertEntity->num_rows;
  int cols = (int)insertEntity->num_cols;
  if (rows <= 0) {
    rows = 1;
  }
  if (cols <= 0) {
    cols = 1;
  }

  const double baseScaleX = insertEntity->scale.x;
  const double baseScaleY = insertEntity->scale.y;
  const SKAffineTransform2D baseTransform = sk_insert_transform(
      insertEntity->ins_pt.x, insertEntity->ins_pt.y, baseScaleX, baseScaleY,
      insertEntity->rotation);
  const SKAffineTransform2D composedBase =
      sk_compose_transform(transform, baseTransform);

  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      const double localX = (double)col * insertEntity->col_spacing;
      const double localY = (double)row * insertEntity->row_spacing;
      SKAffineTransform2D offset = sk_identity_transform();
      offset.tx = localX;
      offset.ty = localY;
      const SKAffineTransform2D finalTransform =
          sk_compose_transform(composedBase, offset);
      if (!sk_parse_block_entities(ctx, blockHeaderObject, finalTransform, stack,
                                   stackCount)) {
        return false;
      }
    }
  }

  return true;
}

static bool sk_parse_entity_object(SKParseContext *ctx, const Dwg_Object *object,
                                   SKAffineTransform2D transform,
                                   const Dwg_Object **stack, int stackCount) {
  if (!ctx || !object || object->supertype != DWG_SUPERTYPE_ENTITY ||
      !object->tio.entity) {
    return true;
  }

  const SKStrokeStyle style = sk_style_from_entity(object->tio.entity);
  const char *layerName = sk_layer_name_from_entity(object->tio.entity);

  switch (object->fixedtype) {
  case DWG_TYPE_LINE: {
    const Dwg_Entity_LINE *line = object->tio.entity->tio.LINE;
    if (!line) {
      return true;
    }
    return sk_append_line(ctx, transform, line->start.x, line->start.y,
                          line->end.x, line->end.y, style, layerName);
  }

  case DWG_TYPE_ARC: {
    const Dwg_Entity_ARC *arc = object->tio.entity->tio.ARC;
    if (!arc) {
      return true;
    }
    return sk_append_arc(ctx, transform, arc->center.x, arc->center.y,
                         arc->radius, arc->start_angle, arc->end_angle, style,
                         layerName);
  }

  case DWG_TYPE_CIRCLE: {
    const Dwg_Entity_CIRCLE *circle = object->tio.entity->tio.CIRCLE;
    if (!circle) {
      return true;
    }
    return sk_append_circle(ctx, transform, circle->center.x, circle->center.y,
                            circle->radius, style, layerName);
  }

  case DWG_TYPE_TEXT: {
    const Dwg_Entity_TEXT *text = object->tio.entity->tio.TEXT;
    if (!text) {
      return true;
    }
    return sk_append_text(ctx, transform, text->ins_pt.x, text->ins_pt.y,
                          text->height, text->rotation, text->text_value, style,
                          layerName);
  }

  case DWG_TYPE_MTEXT: {
    const Dwg_Entity_MTEXT *text = object->tio.entity->tio.MTEXT;
    if (!text) {
      return true;
    }
    const double rotation = atan2(text->x_axis_dir.y, text->x_axis_dir.x);
    return sk_append_text(ctx, transform, text->ins_pt.x, text->ins_pt.y,
                          text->text_height, rotation, text->text, style,
                          layerName);
  }

  case DWG_TYPE_ATTRIB: {
    const Dwg_Entity_ATTRIB *attrib = object->tio.entity->tio.ATTRIB;
    if (!attrib) {
      return true;
    }
    return sk_append_attrib_like_text(
        ctx,
        transform,
        attrib->ins_pt.x,
        attrib->ins_pt.y,
        attrib->height,
        attrib->rotation,
        attrib->text_value,
        style,
        layerName);
  }

  case DWG_TYPE_ATTDEF: {
    const Dwg_Entity_ATTDEF *attdef = object->tio.entity->tio.ATTDEF;
    if (!attdef) {
      return true;
    }
    return sk_append_attrib_like_text(
        ctx,
        transform,
        attdef->ins_pt.x,
        attdef->ins_pt.y,
        attdef->height,
        attdef->rotation,
        attdef->default_value,
        style,
        layerName);
  }

  case DWG_TYPE_LWPOLYLINE: {
    const Dwg_Entity_LWPOLYLINE *lwpolyline = object->tio.entity->tio.LWPOLYLINE;
    return sk_append_lwpolyline(ctx, lwpolyline, transform, style, layerName);
  }

  case DWG_TYPE_POLYLINE_2D: {
    const Dwg_Entity_POLYLINE_2D *polyline = object->tio.entity->tio.POLYLINE_2D;
    const bool closed = polyline && ((polyline->flag & 1) == 1);
    return sk_append_polyline_from_subentities(ctx, object, transform, closed, style, layerName);
  }

  case DWG_TYPE_POLYLINE_3D: {
    const Dwg_Entity_POLYLINE_3D *polyline = object->tio.entity->tio.POLYLINE_3D;
    const bool closed = polyline && ((polyline->flag & 1) == 1);
    return sk_append_polyline_from_subentities(ctx, object, transform, closed, style, layerName);
  }

  case DWG_TYPE_ELLIPSE: {
    const Dwg_Entity_ELLIPSE *ellipse = object->tio.entity->tio.ELLIPSE;
    return sk_append_ellipse(ctx, ellipse, transform, style, layerName);
  }

  case DWG_TYPE_SOLID: {
    const Dwg_Entity_SOLID *solid = object->tio.entity->tio.SOLID;
    if (!solid) {
      return true;
    }
    return sk_append_solid_outline(
        ctx,
        transform,
        solid->corner1.x, solid->corner1.y,
        solid->corner2.x, solid->corner2.y,
        solid->corner3.x, solid->corner3.y,
        solid->corner4.x, solid->corner4.y,
        style,
        layerName);
  }

  case DWG_TYPE__3DFACE: {
    const Dwg_Entity__3DFACE *face = object->tio.entity->tio._3DFACE;
    if (!face) {
      return true;
    }
    return sk_append_solid_outline(
        ctx,
        transform,
        face->corner1.x, face->corner1.y,
        face->corner2.x, face->corner2.y,
        face->corner3.x, face->corner3.y,
        face->corner4.x, face->corner4.y,
        style,
        layerName);
  }

  case DWG_TYPE_DIMENSION_LINEAR: {
    const Dwg_Entity_DIMENSION_LINEAR *dim = object->tio.entity->tio.DIMENSION_LINEAR;
    return sk_append_dimension_linear_like(ctx, transform, dim, style, layerName);
  }

  case DWG_TYPE_DIMENSION_ALIGNED: {
    const Dwg_Entity_DIMENSION_ALIGNED *dim = object->tio.entity->tio.DIMENSION_ALIGNED;
    return sk_append_dimension_aligned_like(ctx, transform, dim, style, layerName);
  }

  case DWG_TYPE_DIMENSION_RADIUS: {
    const Dwg_Entity_DIMENSION_RADIUS *dim = object->tio.entity->tio.DIMENSION_RADIUS;
    if (!dim) {
      return true;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->def_pt.x, dim->def_pt.y,
                                 dim->first_arc_pt.x, dim->first_arc_pt.y, style, layerName)) {
      return false;
    }
    return sk_append_dimension_text(ctx, transform, dim->text_midpt.x, dim->text_midpt.y,
                                    dim->text_rotation, dim->user_text,
                                    dim->act_measurement, style, layerName);
  }

  case DWG_TYPE_DIMENSION_DIAMETER: {
    const Dwg_Entity_DIMENSION_DIAMETER *dim = object->tio.entity->tio.DIMENSION_DIAMETER;
    if (!dim) {
      return true;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->def_pt.x, dim->def_pt.y,
                                 dim->first_arc_pt.x, dim->first_arc_pt.y, style, layerName)) {
      return false;
    }
    return sk_append_dimension_text(ctx, transform, dim->text_midpt.x, dim->text_midpt.y,
                                    dim->text_rotation, dim->user_text,
                                    dim->act_measurement, style, layerName);
  }

  case DWG_TYPE_DIMENSION_ORDINATE: {
    const Dwg_Entity_DIMENSION_ORDINATE *dim = object->tio.entity->tio.DIMENSION_ORDINATE;
    if (!dim) {
      return true;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->feature_location_pt.x, dim->feature_location_pt.y,
                                 dim->leader_endpt.x, dim->leader_endpt.y, style, layerName)) {
      return false;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->leader_endpt.x, dim->leader_endpt.y,
                                 dim->def_pt.x, dim->def_pt.y, style, layerName)) {
      return false;
    }
    return sk_append_dimension_text(ctx, transform, dim->text_midpt.x, dim->text_midpt.y,
                                    dim->text_rotation, dim->user_text,
                                    dim->act_measurement, style, layerName);
  }

  case DWG_TYPE_DIMENSION_ANG3PT: {
    const Dwg_Entity_DIMENSION_ANG3PT *dim = object->tio.entity->tio.DIMENSION_ANG3PT;
    if (!dim) {
      return true;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->center_pt.x, dim->center_pt.y,
                                 dim->xline1_pt.x, dim->xline1_pt.y, style, layerName)) {
      return false;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->center_pt.x, dim->center_pt.y,
                                 dim->xline2_pt.x, dim->xline2_pt.y, style, layerName)) {
      return false;
    }
    return sk_append_dimension_text(ctx, transform, dim->text_midpt.x, dim->text_midpt.y,
                                    dim->text_rotation, dim->user_text,
                                    dim->act_measurement, style, layerName);
  }

  case DWG_TYPE_DIMENSION_ANG2LN: {
    const Dwg_Entity_DIMENSION_ANG2LN *dim = object->tio.entity->tio.DIMENSION_ANG2LN;
    if (!dim) {
      return true;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->xline1start_pt.x, dim->xline1start_pt.y,
                                 dim->xline1end_pt.x, dim->xline1end_pt.y, style, layerName)) {
      return false;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->xline2start_pt.x, dim->xline2start_pt.y,
                                 dim->xline2end_pt.x, dim->xline2end_pt.y, style, layerName)) {
      return false;
    }
    return sk_append_dimension_text(ctx, transform, dim->text_midpt.x, dim->text_midpt.y,
                                    dim->text_rotation, dim->user_text,
                                    dim->act_measurement, style, layerName);
  }

  case DWG_TYPE_HATCH: {
    const Dwg_Entity_HATCH *hatch = object->tio.entity->tio.HATCH;
    return sk_append_hatch_entity(ctx, hatch, transform, style, layerName);
  }

  case DWG_TYPE_LEADER: {
    const Dwg_Entity_LEADER *leader = object->tio.entity->tio.LEADER;
    return sk_append_leader_entity(ctx, leader, transform, style, layerName);
  }

  case DWG_TYPE_MULTILEADER: {
    const Dwg_Entity_MULTILEADER *leader = object->tio.entity->tio.MULTILEADER;
    return sk_append_multileader_entity(ctx, leader, transform, style, layerName);
  }

  case DWG_TYPE_IMAGE: {
    const Dwg_Entity_IMAGE *image = object->tio.entity->tio.IMAGE;
    if (!image) {
      return true;
    }
    return sk_append_image_like_entity(
        ctx,
        image->pt0,
        image->uvec,
        image->vvec,
        image->image_size,
        image->num_clip_verts,
        image->clip_verts,
        transform,
        style,
        layerName);
  }

  case DWG_TYPE_WIPEOUT: {
    const Dwg_Entity_WIPEOUT *wipeout = object->tio.entity->tio.WIPEOUT;
    if (!wipeout) {
      return true;
    }
    return sk_append_image_like_entity(
        ctx,
        wipeout->pt0,
        wipeout->uvec,
        wipeout->vvec,
        wipeout->image_size,
        wipeout->num_clip_verts,
        wipeout->clip_verts,
        transform,
        style,
        layerName);
  }

  case DWG_TYPE_INSERT: {
    const Dwg_Entity_INSERT *insertEntity = object->tio.entity->tio.INSERT;
    return sk_parse_insert_entity(ctx, insertEntity, transform, stack, stackCount);
  }

  case DWG_TYPE_MINSERT: {
    const Dwg_Entity_MINSERT *insertEntity = object->tio.entity->tio.MINSERT;
    return sk_parse_minsert_entity(ctx, insertEntity, transform, stack, stackCount);
  }

  case DWG_TYPE_BLOCK:
  case DWG_TYPE_ENDBLK:
  case DWG_TYPE_SEQEND:
  case DWG_TYPE_VERTEX_2D:
  case DWG_TYPE_VERTEX_3D:
  case DWG_TYPE_VERTEX_MESH:
  case DWG_TYPE_VERTEX_PFACE:
  case DWG_TYPE_VERTEX_PFACE_FACE:
    return true;

  default:
    ctx->result->unsupportedEntityCount += 1;
    sk_track_unsupported(ctx, object->fixedtype);
    return true;
  }
}

static bool sk_parse_root_entities(SKParseContext *ctx) {
  Dwg_Object *modelSpace = dwg_model_space_object(ctx->dwg);
  Dwg_Object *paperSpace = dwg_paper_space_object(ctx->dwg);
  const SKAffineTransform2D identity = sk_identity_transform();
  int parsedRoots = 0;

  if (modelSpace && modelSpace->fixedtype == DWG_TYPE_BLOCK_HEADER) {
    parsedRoots += 1;
    if (!sk_parse_block_entities(ctx, modelSpace, identity, NULL, 0)) {
      return false;
    }
  }

  if (paperSpace && paperSpace->fixedtype == DWG_TYPE_BLOCK_HEADER &&
      paperSpace != modelSpace) {
    parsedRoots += 1;
    if (!sk_parse_block_entities(ctx, paperSpace, identity, NULL, 0)) {
      return false;
    }
  }

  if (parsedRoots > 0) {
    return true;
  }

  // Fallback: if model/paper block headers are unavailable, scan all entities.
  for (BITCODE_BL index = 0; index < ctx->dwg->num_objects; index++) {
    const Dwg_Object *object = &ctx->dwg->object[index];
    if (!sk_parse_entity_object(ctx, object, identity, NULL, 0)) {
      return false;
    }
  }
  return true;
}

int sk_libredwg_parse_file(const char *path, SKCADParseResult *result) {
  return sk_libredwg_parse_file_with_codepage(path, 0, result);
}

int sk_libredwg_parse_file_with_codepage(const char *path, int codepage_override,
                                         SKCADParseResult *result) {
  if (!result) {
    return 0;
  }
  memset(result, 0, sizeof(*result));
  if (!path || !path[0]) {
    sk_set_error(result, "DWG 文件路径为空。");
    return 0;
  }

  Dwg_Data dwg;
  memset(&dwg, 0, sizeof(dwg));

  const int readStatus = dwg_read_file(path, &dwg);
  if (readStatus != 0 && readStatus >= DWG_ERR_CRITICAL && dwg.num_objects == 0) {
    sk_set_error(result, "LibreDWG 读取失败（错误码 %d）。", readStatus);
    dwg_free(&dwg);
    return 0;
  }

  SKParseContext ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.result = result;
  ctx.dwg = &dwg;
  ctx.capacity = 0;
  ctx.textCodepageOverride = codepage_override > 0 ? (BITCODE_RS)codepage_override : 0;
  result->totalObjectCount = (int)dwg.num_objects;

  const bool parsed = sk_parse_root_entities(&ctx);
  if (!parsed) {
    if (!result->errorMessage[0]) {
      sk_set_error(result, "DWG 解析中断。");
    }
    if (result->primitives) {
      for (int index = 0; index < result->primitiveCount; index++) {
        if (result->primitives[index].text) {
          free(result->primitives[index].text);
          result->primitives[index].text = NULL;
        }
        if (result->primitives[index].layerName) {
          free(result->primitives[index].layerName);
          result->primitives[index].layerName = NULL;
        }
      }
      free(result->primitives);
      result->primitives = NULL;
      result->primitiveCount = 0;
      result->totalObjectCount = 0;
      result->unsupportedEntityCount = 0;
    }
    dwg_free(&dwg);
    return 0;
  }

  if (result->primitiveCount <= 0) {
    if (!result->errorMessage[0]) {
      char stats[256];
      stats[0] = '\0';
      for (int index = 0; index < ctx.unsupportedTypeCount && index < 4; index++) {
        const char *name = sk_entity_type_name(ctx.unsupportedTypes[index].type);
        char line[64];
        snprintf(line, sizeof(line), "%s:%d%s", name, ctx.unsupportedTypes[index].count,
                 index + 1 < ctx.unsupportedTypeCount && index < 3 ? ", " : "");
        strncat(stats, line, sizeof(stats) - strlen(stats) - 1);
      }
      if (stats[0]) {
        if (readStatus != 0) {
          sk_set_error(result,
                       "未识别到可绘制实体（读取状态 %d）。已支持 LINE/ARC/CIRCLE/TEXT/"
                       "MTEXT/LWPOLYLINE/POLYLINE/ELLIPSE/INSERT/MINSERT/DIMENSION/"
                       "HATCH/LEADER/MULTILEADER/SOLID/3DFACE；当前主要未支持：%s。",
                       readStatus, stats);
        } else {
          sk_set_error(result,
                       "未识别到可绘制实体。已支持 LINE/ARC/CIRCLE/TEXT/MTEXT/"
                       "LWPOLYLINE/POLYLINE/ELLIPSE/INSERT/MINSERT/DIMENSION/"
                       "HATCH/LEADER/MULTILEADER/SOLID/3DFACE；当前主要未支持：%s。",
                       stats);
        }
      } else {
        if (readStatus != 0) {
          sk_set_error(result,
                       "未识别到可绘制实体（读取状态 %d，当前支持 LINE / ARC / CIRCLE / "
                       "TEXT / MTEXT / LWPOLYLINE / POLYLINE / ELLIPSE / INSERT / "
                       "MINSERT / DIMENSION / HATCH / LEADER / MULTILEADER / SOLID / "
                       "3DFACE）。",
                       readStatus);
        } else {
          sk_set_error(result,
                       "未识别到可绘制实体（当前支持 LINE / ARC / CIRCLE / TEXT / "
                       "MTEXT / LWPOLYLINE / POLYLINE / ELLIPSE / INSERT / MINSERT / "
                       "DIMENSION / HATCH / LEADER / MULTILEADER / SOLID / 3DFACE）。");
        }
      }
    }
    if (result->primitives) {
      for (int index = 0; index < result->primitiveCount; index++) {
        if (result->primitives[index].text) {
          free(result->primitives[index].text);
          result->primitives[index].text = NULL;
        }
        if (result->primitives[index].layerName) {
          free(result->primitives[index].layerName);
          result->primitives[index].layerName = NULL;
        }
      }
      free(result->primitives);
      result->primitives = NULL;
      result->primitiveCount = 0;
      result->totalObjectCount = 0;
      result->unsupportedEntityCount = 0;
    }
    dwg_free(&dwg);
    return 0;
  }

  dwg_free(&dwg);
  return 1;
}

void sk_libredwg_free_parse_result(SKCADParseResult *result) {
  if (!result) {
    return;
  }

  if (result->primitives) {
    for (int index = 0; index < result->primitiveCount; index++) {
      if (result->primitives[index].text) {
        free(result->primitives[index].text);
        result->primitives[index].text = NULL;
      }
      if (result->primitives[index].layerName) {
        free(result->primitives[index].layerName);
        result->primitives[index].layerName = NULL;
      }
    }
    free(result->primitives);
  }

  memset(result, 0, sizeof(*result));
}
