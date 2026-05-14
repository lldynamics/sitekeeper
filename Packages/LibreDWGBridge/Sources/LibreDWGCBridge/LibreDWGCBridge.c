#include "LibreDWGCBridge.h"

#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "dwg.h"
#include "bits.h"
#include "codepages.h"

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
  int parseOptions;
  BITCODE_RS textCodepageOverride;
  bool hasTextCodepageOverride;
  struct {
    int type;
    int count;
  } unsupportedTypes[16];
  int unsupportedTypeCount;
} SKParseContext;

typedef struct SKPointBuffer {
  SKCADPoint *points;
  int count;
  int capacity;
} SKPointBuffer;

typedef struct SKStrokeStyle {
  unsigned int rgb;
  double width;
} SKStrokeStyle;

#define SK_MAX_RECURSION_DEPTH 48
#define SK_MAX_PRIMITIVE_COUNT 260000
#define SK_MAX_DWG_OBJECT_COUNT 500000
#define SK_MAX_PRIMITIVE_BUFFER_BYTES (160ULL * 1024ULL * 1024ULL)
#define SK_MAX_RAW_TEXT_SAMPLE_BYTES 1024

static void sk_fill_budget_metadata(SKCADParseResult *result) {
  if (!result) {
    return;
  }
  result->primitiveLimit = SK_MAX_PRIMITIVE_COUNT;
  result->objectLimit = SK_MAX_DWG_OBJECT_COUNT;
  result->primitiveMemoryBudget = SK_MAX_PRIMITIVE_BUFFER_BYTES;
  result->estimatedPrimitiveMemory = 0;
}

static void sk_set_error(SKCADParseResult *result, const char *fmt, ...) {
  if (!result) {
    return;
  }
  va_list args;
  va_start(args, fmt);
  vsnprintf(result->errorMessage, sizeof(result->errorMessage), fmt, args);
  va_end(args);
}

static void sk_copy_fixed(char *destination, size_t capacity, const char *source) {
  if (!destination || capacity == 0) {
    return;
  }
  destination[0] = '\0';
  if (!source || !source[0]) {
    return;
  }
  snprintf(destination, capacity, "%s", source);
}

static void sk_fill_version_metadata(SKCADParseResult *result, const Dwg_Data *dwg,
                                     int readStatus) {
  if (!result || !dwg) {
    return;
  }
  result->readStatus = readStatus;
  result->dwgVersion = (int)dwg->header.version;
  result->dwgFromVersion = (int)dwg->header.from_version;
  result->dwgHeaderDwgVersion = (int)dwg->header.dwg_version;
  result->dwgHeaderMaintVersion = (int)dwg->header.maint_version;

  const Dwg_Versions *version = dwg_version_struct(dwg->header.version);
  if (version) {
    sk_copy_fixed(result->dwgVersionCode, sizeof(result->dwgVersionCode), version->hdr);
    sk_copy_fixed(result->dwgVersionType, sizeof(result->dwgVersionType), version->type);
    sk_copy_fixed(result->dwgVersionDescription, sizeof(result->dwgVersionDescription), version->desc);
  }
}

static bool sk_read_status_blocks_geometry_parse(int readStatus) {
  if (readStatus == DWG_NOERR) {
    return false;
  }
  if ((readStatus & DWG_ERR_CLASSESNOTFOUND) != 0 ||
      (readStatus & DWG_ERR_SECTIONNOTFOUND) != 0 ||
      (readStatus & DWG_ERR_PAGENOTFOUND) != 0 ||
      (readStatus & DWG_ERR_INTERNALERROR) != 0 ||
      (readStatus & DWG_ERR_INVALIDDWG) != 0 ||
      (readStatus & DWG_ERR_IOERROR) != 0 ||
      (readStatus & DWG_ERR_OUTOFMEM) != 0) {
    return true;
  }
  return false;
}

static BITCODE_RS sk_dwg_codepage_from_external(int codepage) {
  switch (codepage) {
  case 0:
    return 0;
  case 932:
    return CP_ANSI_932;
  case 936:
  case 54936:
    return CP_ANSI_936;
  case 949:
    return CP_ANSI_949;
  case 950:
    return CP_ANSI_950;
  case 65001:
    return CP_UTF8;
  case 1250:
    return CP_ANSI_1250;
  case 1251:
    return CP_ANSI_1251;
  case 1252:
    return CP_ANSI_1252;
  case 1253:
    return CP_ANSI_1253;
  case 1254:
    return CP_ANSI_1254;
  case 1255:
    return CP_ANSI_1255;
  case 1256:
    return CP_ANSI_1256;
  case 1257:
    return CP_ANSI_1257;
  case 1258:
    return CP_ANSI_1258;
  default:
    return (BITCODE_RS)codepage;
  }
}

static int sk_external_codepage_from_dwg(BITCODE_RS codepage) {
  switch (codepage) {
  case CP_UTF8:
    return 65001;
  case CP_ANSI_932:
    return 932;
  case CP_ANSI_936:
    return 936;
  case CP_ANSI_949:
    return 949;
  case CP_ANSI_950:
    return 950;
  case CP_ANSI_1250:
    return 1250;
  case CP_ANSI_1251:
    return 1251;
  case CP_ANSI_1252:
    return 1252;
  case CP_ANSI_1253:
    return 1253;
  case CP_ANSI_1254:
    return 1254;
  case CP_ANSI_1255:
    return 1255;
  case CP_ANSI_1256:
    return 1256;
  case CP_ANSI_1257:
    return 1257;
  case CP_ANSI_1258:
    return 1258;
  default:
    return (int)codepage;
  }
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
  if (required > SK_MAX_PRIMITIVE_COUNT) {
    sk_set_error(ctx->result, "DWG 实体数量超过预览上限，已停止解析以避免内存不足。");
    return false;
  }
  if (required <= ctx->capacity) {
    return true;
  }

  int nextCapacity = ctx->capacity > 0 ? ctx->capacity : 256;
  while (nextCapacity < required) {
    if (nextCapacity >= SK_MAX_PRIMITIVE_COUNT) {
      sk_set_error(ctx->result, "DWG 实体数量过大，无法分配内存。");
      return false;
    }
    const int doubled = nextCapacity << 1;
    nextCapacity = doubled > SK_MAX_PRIMITIVE_COUNT ? SK_MAX_PRIMITIVE_COUNT : doubled;
  }

  if ((size_t)nextCapacity > (size_t)(SK_MAX_PRIMITIVE_BUFFER_BYTES / sizeof(SKCADPrimitive))) {
    sk_set_error(
        ctx->result,
        "DWG 预览 primitive 缓冲区超过内存预算（上限 %.1f MB），已停止解析。",
        (double)SK_MAX_PRIMITIVE_BUFFER_BYTES / 1024.0 / 1024.0);
    return false;
  }
  const size_t allocationBytes = (size_t)nextCapacity * sizeof(SKCADPrimitive);
  const unsigned long long previousBufferBytes =
      (unsigned long long)ctx->capacity * sizeof(SKCADPrimitive);
  const unsigned long long previousPointBytes =
      ctx->result->estimatedPrimitiveMemory > previousBufferBytes
          ? ctx->result->estimatedPrimitiveMemory - previousBufferBytes
          : 0;
  if ((unsigned long long)allocationBytes + previousPointBytes >
      SK_MAX_PRIMITIVE_BUFFER_BYTES) {
    sk_set_error(
        ctx->result,
        "DWG 预览几何缓冲区超过内存预算（上限 %.1f MB），已停止解析。",
        (double)SK_MAX_PRIMITIVE_BUFFER_BYTES / 1024.0 / 1024.0);
    return false;
  }

  SKCADPrimitive *next = (SKCADPrimitive *)realloc(
      ctx->result->primitives, allocationBytes);
  if (!next) {
    sk_set_error(ctx->result, "DWG 预览内存分配失败。");
    return false;
  }

  memset(next + ctx->capacity, 0,
         (size_t)(nextCapacity - ctx->capacity) * sizeof(SKCADPrimitive));
  ctx->result->primitives = next;
  ctx->capacity = nextCapacity;
  ctx->result->estimatedPrimitiveMemory =
      (unsigned long long)allocationBytes + previousPointBytes;
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

static char *sk_hex_copy(const char *text) {
  if (!text || !text[0]) {
    return NULL;
  }
  static const char digits[] = "0123456789ABCDEF";
  const unsigned char *bytes = (const unsigned char *)text;
  const size_t len = strlen(text);
  const size_t maxBytes = len > SK_MAX_RAW_TEXT_SAMPLE_BYTES ? SK_MAX_RAW_TEXT_SAMPLE_BYTES : len;
  const size_t suffix = len > maxBytes ? 3 : 0;
  char *out = (char *)malloc(maxBytes * 3 + suffix + 1);
  if (!out) {
    return NULL;
  }
  size_t cursor = 0;
  for (size_t index = 0; index < maxBytes; index++) {
    if (index > 0) {
      out[cursor++] = ' ';
    }
    out[cursor++] = digits[(bytes[index] >> 4) & 0x0F];
    out[cursor++] = digits[bytes[index] & 0x0F];
  }
  if (suffix) {
    out[cursor++] = '.';
    out[cursor++] = '.';
    out[cursor++] = '.';
  }
  out[cursor] = '\0';
  return out;
}

static void sk_free_primitive_members(SKCADPrimitive *primitive) {
  if (!primitive) {
    return;
  }
  if (primitive->text) {
    free(primitive->text);
    primitive->text = NULL;
  }
  if (primitive->rawTextBytesHex) {
    free(primitive->rawTextBytesHex);
    primitive->rawTextBytesHex = NULL;
  }
  if (primitive->layerName) {
    free(primitive->layerName);
    primitive->layerName = NULL;
  }
  if (primitive->textStyleName) {
    free(primitive->textStyleName);
    primitive->textStyleName = NULL;
  }
  if (primitive->fontFile) {
    free(primitive->fontFile);
    primitive->fontFile = NULL;
  }
  if (primitive->bigFontFile) {
    free(primitive->bigFontFile);
    primitive->bigFontFile = NULL;
  }
  if (primitive->points) {
    free(primitive->points);
    primitive->points = NULL;
  }
  primitive->pointCount = 0;
}

static void sk_free_xref_reference(SKCADXrefReference *xref) {
  if (!xref) {
    return;
  }
  if (xref->name) {
    free(xref->name);
    xref->name = NULL;
  }
  if (xref->savedPath) {
    free(xref->savedPath);
    xref->savedPath = NULL;
  }
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

static int sk_read_utf8_codepoint(const unsigned char **cursor) {
  const unsigned char *bytes = *cursor;
  if (!bytes || !*bytes) {
    return -1;
  }
  if (bytes[0] <= 0x7F) {
    *cursor = bytes + 1;
    return bytes[0];
  }
  if ((bytes[0] & 0xE0) == 0xC0 &&
      (bytes[1] & 0xC0) == 0x80 &&
      bytes[0] != 0xC0 && bytes[0] != 0xC1) {
    *cursor = bytes + 2;
    return ((bytes[0] & 0x1F) << 6) | (bytes[1] & 0x3F);
  }
  if ((bytes[0] & 0xF0) == 0xE0 &&
      (bytes[1] & 0xC0) == 0x80 &&
      (bytes[2] & 0xC0) == 0x80 &&
      !(bytes[0] == 0xE0 && bytes[1] < 0xA0)) {
    *cursor = bytes + 3;
    return ((bytes[0] & 0x0F) << 12) |
           ((bytes[1] & 0x3F) << 6) |
           (bytes[2] & 0x3F);
  }
  if ((bytes[0] & 0xF8) == 0xF0 &&
      (bytes[1] & 0xC0) == 0x80 &&
      (bytes[2] & 0xC0) == 0x80 &&
      (bytes[3] & 0xC0) == 0x80 &&
      bytes[0] <= 0xF4 &&
      !(bytes[0] == 0xF0 && bytes[1] < 0x90) &&
      !(bytes[0] == 0xF4 && bytes[1] > 0x8F)) {
    *cursor = bytes + 4;
    return ((bytes[0] & 0x07) << 18) |
           ((bytes[1] & 0x3F) << 12) |
           ((bytes[2] & 0x3F) << 6) |
           (bytes[3] & 0x3F);
  }
  *cursor = bytes + 1;
  return -1;
}

static bool sk_codepoint_is_cjk(int codepoint) {
  return (codepoint >= 0x3400 && codepoint <= 0x4DBF) ||
         (codepoint >= 0x4E00 && codepoint <= 0x9FFF) ||
         (codepoint >= 0xF900 && codepoint <= 0xFAFF);
}

static bool sk_codepoint_is_east_asian_punctuation(int codepoint) {
  return codepoint >= 0x3000 && codepoint <= 0x303F;
}

static bool sk_codepoint_is_halfwidth_katakana(int codepoint) {
  return codepoint >= 0xFF61 && codepoint <= 0xFF9F;
}

static bool sk_codepoint_is_fullwidth_ascii(int codepoint) {
  return codepoint >= 0xFF01 && codepoint <= 0xFF5E;
}

static bool sk_codepoint_is_box_drawing(int codepoint) {
  return codepoint >= 0x2500 && codepoint <= 0x257F;
}

static bool sk_codepoint_is_private_use(int codepoint) {
  return codepoint >= 0xE000 && codepoint <= 0xF8FF;
}

static bool sk_contains_utf8(const char *text, const char *needle) {
  return text && needle && strstr(text, needle) != NULL;
}

static int sk_cad_vocabulary_score(const char *text) {
  if (!text || !text[0]) {
    return 0;
  }
  const char *commonTerms[] = {
    "平面", "立面", "剖面", "详图", "节点", "标高", "轴线", "尺寸",
    "配电", "回路", "照明", "插座", "桥架", "线管", "接地", "负荷", "施工",
    "建筑", "结构", "电气", "给排水", "消防", "弱电", "系统图", "配线",
    "平面圖", "立面圖", "剖面圖", "詳圖", "節點", "標高", "軸線", "尺寸",
    "配電", "迴路", "照明", "插座", "橋架", "線管", "接地", "負荷", "施工",
    "建築", "結構", "電氣", "給排水", "消防", "弱電", "系統圖", "配線"
  };
  int score = 0;
  for (size_t index = 0; index < sizeof(commonTerms) / sizeof(commonTerms[0]); index++) {
    if (sk_contains_utf8(text, commonTerms[index])) {
      score += 18;
    }
  }

  const char *suspiciousGlyphs[] = {
    "Ê", "Ð", "Ä", "Ã", "Â", "Ó", "Æ", "Ë", "·", "µ", "Ç",
    "涓", "鐨", "鏂", "鍙", "杩", "锛", "銆", "鈥", "澶", "笁",
    "鍗", "闂", "瀛", "妗", "骞", "鐢", "皵", "寤虹", "缁撴",
    "缁欐", "娑堥", "鏍囬", "杞寸", "閰嶇", "鐓ф", "鍥炶",
    "鎻掑", "绾跨", "璐熻", "绯荤", "鍥剧"
  };
  for (size_t index = 0; index < sizeof(suspiciousGlyphs) / sizeof(suspiciousGlyphs[0]); index++) {
    if (sk_contains_utf8(text, suspiciousGlyphs[index])) {
      score -= 18;
    }
  }
  return score;
}

static int sk_text_quality_score(const char *text) {
  if (!text || !text[0] || !sk_is_valid_utf8(text)) {
    return -100000;
  }
  int score = 0;
  const unsigned char *cursor = (const unsigned char *)text;
  while (*cursor) {
    const int codepoint = sk_read_utf8_codepoint(&cursor);
    if (codepoint < 0) {
      score -= 30;
      continue;
    }
    if (sk_codepoint_is_cjk(codepoint)) {
      score += 12;
    } else if (sk_codepoint_is_east_asian_punctuation(codepoint)) {
      score += 2;
    } else if (sk_codepoint_is_fullwidth_ascii(codepoint)) {
      score += 1;
    } else if (sk_codepoint_is_halfwidth_katakana(codepoint)) {
      score -= 16;
    } else if (sk_codepoint_is_box_drawing(codepoint)) {
      score -= 18;
    } else if (sk_codepoint_is_private_use(codepoint)) {
      score -= 36;
    } else if (codepoint == 0xFFFD) {
      score -= 40;
    } else if (codepoint >= 0x00A0 && codepoint <= 0x00FF) {
      // CAD Chinese mojibake often appears as Latin-1 supplement glyphs like ÊÐ.
      score -= 6;
    } else if (codepoint == '?') {
      score -= 4;
    } else if (codepoint < 0x20 && codepoint != '\n' && codepoint != '\r' && codepoint != '\t') {
      score -= 12;
    } else if (codepoint < 0x7F) {
      score += 1;
    }
  }
  score += sk_cad_vocabulary_score(text);
  return score;
}

static int sk_codepage_preference_bias(BITCODE_RS candidateCodepage,
                                       BITCODE_RS preferredCodepage) {
  int bias = 0;
  if (preferredCodepage > 0 && candidateCodepage == preferredCodepage) {
    bias += 20;
  }

  switch (candidateCodepage) {
  case CP_ANSI_936:
    bias += 18;
    break;
  case CP_UTF8:
    bias += 6;
    break;
  case CP_ANSI_950:
    if (preferredCodepage != CP_ANSI_950) {
      bias -= 6;
    }
    break;
  case CP_ANSI_932:
  case CP_ANSI_949:
    if (preferredCodepage != candidateCodepage) {
      bias -= 24;
    }
    break;
  default:
    break;
  }
  return bias;
}

static bool sk_text_looks_latin1_mojibake(const char *text) {
  if (!text || !sk_is_valid_utf8(text)) {
    return false;
  }
  int highLatinCount = 0;
  int cjkCount = 0;
  const unsigned char *cursor = (const unsigned char *)text;
  while (*cursor) {
    const int codepoint = sk_read_utf8_codepoint(&cursor);
    if (sk_codepoint_is_cjk(codepoint)) {
      cjkCount += 1;
    } else if (codepoint >= 0x00A0 && codepoint <= 0x00FF) {
      highLatinCount += 1;
    }
  }
  return cjkCount == 0 && highLatinCount > 0;
}

static char *sk_latin1_bytes_from_utf8(const char *text) {
  if (!text || !sk_text_looks_latin1_mojibake(text)) {
    return NULL;
  }
  const size_t maxLen = strlen(text);
  char *bytes = (char *)malloc(maxLen + 1);
  if (!bytes) {
    return NULL;
  }
  size_t out = 0;
  const unsigned char *cursor = (const unsigned char *)text;
  while (*cursor) {
    const int codepoint = sk_read_utf8_codepoint(&cursor);
    if (codepoint < 0 || codepoint > 0xFF || codepoint == 0) {
      free(bytes);
      return NULL;
    }
    bytes[out++] = (char)(unsigned char)codepoint;
  }
  bytes[out] = '\0';
  return bytes;
}

static void sk_choose_candidate(char **best, int *bestScore, int *bestCodepage,
                                char *candidate, BITCODE_RS candidateCodepage,
                                BITCODE_RS preferredCodepage) {
  if (!candidate || !candidate[0]) {
    if (candidate) {
      free(candidate);
    }
    return;
  }
  const int score = sk_text_quality_score(candidate) +
                    sk_codepage_preference_bias(candidateCodepage,
                                                preferredCodepage);
  if (!*best || score > *bestScore) {
    if (*best) {
      free(*best);
    }
    *best = candidate;
    *bestScore = score;
    if (bestCodepage) {
      *bestCodepage = sk_external_codepage_from_dwg(candidateCodepage);
    }
  } else {
    free(candidate);
  }
}

static char *sk_utf8_copy_with_codepage(const char *text, BITCODE_RS codepage,
                                        int *chosenCodepage) {
  if (!text || !text[0]) {
    return NULL;
  }

  char *best = NULL;
  int bestScore = -1000000;
  int bestCodepage = 0;
  const bool isValidUTF8 = sk_is_valid_utf8(text);

  if (isValidUTF8) {
    sk_choose_candidate(&best, &bestScore, &bestCodepage, sk_strdup_safe(text),
                        CP_UTF8, codepage);
  }

  // DWG codepage sometimes comes as 0 in the header for legacy drawings.
  // Try header/manual codepage, then common East-Asia fallbacks.
  const BITCODE_RS fallbackCodepages[] = {
      CP_ANSI_936, CP_ANSI_950, CP_ANSI_932, CP_ANSI_949, CP_UTF8
  };
  if (!isValidUTF8 && codepage > 0) {
    sk_choose_candidate(&best, &bestScore, &bestCodepage,
                        sk_copy_converted_utf8(text, codepage), codepage,
                        codepage);
  }
  if (isValidUTF8 && codepage > 0 && codepage != CP_UTF8 && sk_text_looks_latin1_mojibake(text)) {
    char *latin1Bytes = sk_latin1_bytes_from_utf8(text);
    if (latin1Bytes) {
      sk_choose_candidate(&best, &bestScore, &bestCodepage,
                          sk_copy_converted_utf8(latin1Bytes, codepage),
                          codepage, codepage);
      free(latin1Bytes);
    }
  }

  for (size_t index = 0; index < sizeof(fallbackCodepages) / sizeof(fallbackCodepages[0]); index++) {
    const BITCODE_RS fallback = fallbackCodepages[index];
    if (fallback == codepage) {
      continue;
    }
    if (isValidUTF8) {
      if (!sk_text_looks_latin1_mojibake(text)) {
        continue;
      }
      char *latin1Bytes = sk_latin1_bytes_from_utf8(text);
      if (latin1Bytes) {
        sk_choose_candidate(&best, &bestScore, &bestCodepage,
                            sk_copy_converted_utf8(latin1Bytes, fallback),
                            fallback, codepage);
        free(latin1Bytes);
      }
    } else {
      sk_choose_candidate(&best, &bestScore, &bestCodepage,
                          sk_copy_converted_utf8(text, fallback), fallback,
                          codepage);
    }
  }
  if (best) {
    if (chosenCodepage) {
      *chosenCodepage = bestCodepage;
    }
    return best;
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
  if (chosenCodepage) {
    *chosenCodepage = 0;
  }
  return lossy;
}

static char *sk_utf8_copy(const char *text, BITCODE_RS codepage) {
  return sk_utf8_copy_with_codepage(text, codepage, NULL);
}

static void sk_append_normalized_utf8(char *destination, size_t capacity,
                                      size_t *length, const char *value) {
  if (!destination || !length || !value || capacity == 0) {
    return;
  }
  while (*value && *length + 1 < capacity) {
    destination[*length] = *value;
    *length += 1;
    value += 1;
  }
  destination[*length] = '\0';
}

static char sk_ascii_lower(char value) {
  if (value >= 'A' && value <= 'Z') {
    return (char)(value - 'A' + 'a');
  }
  return value;
}

static char *sk_normalize_cad_text(const char *text) {
  if (!text || !text[0]) {
    return NULL;
  }

  const size_t length = strlen(text);
  const size_t capacity = length * 4 + 1;
  char *result = (char *)malloc(capacity);
  if (!result) {
    return sk_strdup_safe(text);
  }

  size_t out = 0;
  for (size_t index = 0; index < length;) {
    const unsigned char current = (const unsigned char)text[index];
    if (current == '%' && index + 2 < length && text[index + 1] == '%') {
      switch (sk_ascii_lower(text[index + 2])) {
      case 'c':
        sk_append_normalized_utf8(result, capacity, &out, "\xCE\xA6");
        index += 3;
        continue;
      case 'd':
        sk_append_normalized_utf8(result, capacity, &out, "\xC2\xB0");
        index += 3;
        continue;
      case 'p':
        sk_append_normalized_utf8(result, capacity, &out, "\xC2\xB1");
        index += 3;
        continue;
      case '%':
        sk_append_normalized_utf8(result, capacity, &out, "%");
        index += 3;
        continue;
      case 'u':
      case 'o':
        index += 3;
        continue;
      default:
        break;
      }
    }

    if (current == '\\' && index + 1 < length) {
      const char code = sk_ascii_lower(text[index + 1]);
      switch (code) {
      case 'p':
        sk_append_normalized_utf8(result, capacity, &out, "\n");
        index += 2;
        continue;
      case '~':
        sk_append_normalized_utf8(result, capacity, &out, " ");
        index += 2;
        continue;
      case 'l':
      case 'o':
      case 'k':
        index += 2;
        continue;
      case 'a':
      case 'c':
      case 'f':
      case 'h':
      case 'w':
      case 'q':
      case 't':
        index += 2;
        while (index < length && text[index] != ';') {
          index += 1;
        }
        if (index < length && text[index] == ';') {
          index += 1;
        }
        continue;
      case 's':
        index += 2;
        while (index < length && text[index] != ';') {
          const char stacked = text[index];
          if (stacked == '#' || stacked == '^') {
            sk_append_normalized_utf8(result, capacity, &out, "/");
          } else if ((unsigned char)stacked >= 0x20) {
            char buffer[2] = {stacked, '\0'};
            sk_append_normalized_utf8(result, capacity, &out, buffer);
          }
          index += 1;
        }
        if (index < length && text[index] == ';') {
          index += 1;
        }
        continue;
      default:
        break;
      }
    }

    if (current < 0x20) {
      if (current == '\n' || current == '\r') {
        sk_append_normalized_utf8(result, capacity, &out, "\n");
      } else if (current == '\t') {
        sk_append_normalized_utf8(result, capacity, &out, " ");
      }
      index += 1;
      continue;
    }

    if (out + 1 >= capacity) {
      break;
    }
    result[out++] = (char)current;
    result[out] = '\0';
    index += 1;
  }

  while (out > 0 && (result[out - 1] == ' ' || result[out - 1] == '\n' ||
                     result[out - 1] == '\r' || result[out - 1] == '\t')) {
    out -= 1;
  }
  result[out] = '\0';

  if (!result[0]) {
    free(result);
    return NULL;
  }
  return result;
}

static BITCODE_RS sk_context_codepage(const SKParseContext *ctx) {
  if (!ctx) {
    return 0;
  }
  return ctx->hasTextCodepageOverride
             ? ctx->textCodepageOverride
             : (ctx->dwg ? ctx->dwg->header.codepage : 0);
}

static char *sk_context_utf8_copy(const SKParseContext *ctx, const char *text) {
  return sk_utf8_copy(text, sk_context_codepage(ctx));
}

static char *sk_context_utf8_copy_with_codepage(const SKParseContext *ctx,
                                                const char *text,
                                                int *chosenCodepage) {
  return sk_utf8_copy_with_codepage(text, sk_context_codepage(ctx), chosenCodepage);
}

static void sk_append_summary_part(char *destination, size_t capacity,
                                   const char *part) {
  if (!destination || capacity == 0 || !part || !part[0]) {
    return;
  }
  const size_t used = strlen(destination);
  if (used + 1 >= capacity) {
    return;
  }
  strncat(destination, part, capacity - used - 1);
}

static void sk_write_style_table_summary(SKCADParseResult *result,
                                         const Dwg_Data *dwg) {
  if (!result || !dwg || !dwg->object || dwg->num_objects == 0) {
    return;
  }

  char summary[sizeof(result->styleTableSummary)];
  summary[0] = '\0';
  int totalStyles = 0;
  int sampledStyles = 0;

  for (BITCODE_BL index = 0; index < dwg->num_objects; index++) {
    const Dwg_Object *object = &dwg->object[index];
    if (!object || object->fixedtype != DWG_TYPE_STYLE || !object->tio.object) {
      continue;
    }
    const Dwg_Object_STYLE *style = object->tio.object->tio.STYLE;
    if (!style) {
      continue;
    }

    totalStyles += 1;
    if (sampledStyles >= 8) {
      continue;
    }

    char *name = sk_utf8_copy(style->name, dwg->header.codepage);
    char *font = sk_utf8_copy(style->font_file, dwg->header.codepage);
    char *bigFont = sk_utf8_copy(style->bigfont_file, dwg->header.codepage);
    char item[160];
    snprintf(item, sizeof(item), "%s%s/%s/%s",
             sampledStyles > 0 ? "；" : "",
             name && name[0] ? name : "-",
             font && font[0] ? font : "-",
             bigFont && bigFont[0] ? bigFont : "-");
    sk_append_summary_part(summary, sizeof(summary), item);
    free(name);
    free(font);
    free(bigFont);
    sampledStyles += 1;
  }

  if (totalStyles > sampledStyles) {
    char suffix[64];
    snprintf(suffix, sizeof(suffix), "；等 %d 个 STYLE", totalStyles);
    sk_append_summary_part(summary, sizeof(summary), suffix);
  } else if (totalStyles > 0) {
    char suffix[64];
    snprintf(suffix, sizeof(suffix), "；共 %d 个 STYLE", totalStyles);
    sk_append_summary_part(summary, sizeof(summary), suffix);
  }

  sk_copy_fixed(result->styleTableSummary, sizeof(result->styleTableSummary),
                summary);
}

static bool sk_text_looks_suspicious(const char *text) {
  if (!text || !text[0] || !sk_is_valid_utf8(text)) {
    return true;
  }
  if (sk_text_looks_latin1_mojibake(text)) {
    return true;
  }
  if (strstr(text, "\xEF\xBF\xBD") != NULL) {
    return true;
  }
  return sk_text_quality_score(text) < -4;
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
                                          const Dwg_Object_LAYER *layer,
                                          const SKStrokeStyle *blockStyle,
                                          bool inheritsLayerZero) {
  int lw100th = dxf_cvt_lweight((BITCODE_BSd)linewt);
  if ((lw100th == -2 || (lw100th == -1 && inheritsLayerZero)) &&
      blockStyle) {
    return blockStyle->width;
  }
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

static SKStrokeStyle sk_style_from_entity(const Dwg_Object_Entity *entity,
                                          const SKStrokeStyle *blockStyle) {
  SKStrokeStyle style;
  style.rgb = sk_default_rgb();
  style.width = sk_default_stroke_width();
  if (!entity) {
    return style;
  }

  const Dwg_Object_LAYER *layer = dwg_get_entity_layer(entity);
  const char *layerName = layer ? layer->name : NULL;
  const bool inheritsLayerZero =
      blockStyle && (!layerName || !layerName[0] || strcmp(layerName, "0") == 0);
  const Dwg_Color *source = &entity->color;
  const bool byBlock = source->method == DWG_COLOR_METHOD_BYBLOCK ||
                       source->index == 0;
  const bool byLayer = source->method == DWG_COLOR_METHOD_BYLAYER ||
                       source->index == 256 ||
                       source->method == DWG_COLOR_METHOD_VOID;
  if ((byBlock || (byLayer && inheritsLayerZero)) && blockStyle) {
    style.rgb = blockStyle->rgb;
  } else if (byLayer && layer) {
    source = &layer->color;
    const unsigned int rgb = sk_rgb_from_color(source);
    style.rgb = rgb != 0 ? rgb : sk_default_rgb();
  } else {
    unsigned int rgb = sk_rgb_from_color(source);
    if (rgb == 0 && layer && source != &layer->color) {
      rgb = sk_rgb_from_color(&layer->color);
    }
    style.rgb = rgb != 0 ? rgb : sk_default_rgb();
  }
  style.width = sk_stroke_width_from_linewt(entity->linewt, layer, blockStyle,
                                            inheritsLayerZero);
  return style;
}

static const char *sk_layer_name_from_entity(const Dwg_Object_Entity *entity,
                                             const char *blockLayerName) {
  if (!entity) {
    return "0";
  }
  const Dwg_Object_LAYER *layer = dwg_get_entity_layer(entity);
  if (!layer || !layer->name || !layer->name[0]) {
    return (blockLayerName && blockLayerName[0]) ? blockLayerName : "0";
  }
  if (strcmp(layer->name, "0") == 0 && blockLayerName && blockLayerName[0]) {
    return blockLayerName;
  }
  return layer->name;
}

static const Dwg_Object_STYLE *sk_text_style_from_ref(const SKParseContext *ctx,
                                                      BITCODE_H styleRef) {
  if (!ctx || !ctx->dwg || !styleRef) {
    return NULL;
  }
  const Dwg_Object *object = styleRef->obj ? styleRef->obj : dwg_ref_object(ctx->dwg, styleRef);
  if (!object || object->fixedtype != DWG_TYPE_STYLE || !object->tio.object) {
    return NULL;
  }
  return object->tio.object->tio.STYLE;
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
  case DWG_TYPE_PROXY_ENTITY:
    return "PROXY_ENTITY/AEC";
  case DWG_TYPE_PROXY_OBJECT:
    return "PROXY_OBJECT/AEC";
  case DWG_TYPE_DYNAMICBLOCKPROXYNODE:
    return "DYNAMICBLOCKPROXYNODE";
  case DWG_TYPE_POLYLINE_3D:
    return "POLYLINE_3D";
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

static void sk_write_unsupported_summary(const SKParseContext *ctx) {
  if (!ctx || !ctx->result) {
    return;
  }
  ctx->result->unsupportedEntitySummary[0] = '\0';
  for (int index = 0; index < ctx->unsupportedTypeCount && index < 8; index++) {
    const char *name = sk_entity_type_name(ctx->unsupportedTypes[index].type);
    char line[64];
    snprintf(line, sizeof(line), "%s:%d%s", name, ctx->unsupportedTypes[index].count,
             index + 1 < ctx->unsupportedTypeCount && index < 7 ? ", " : "");
    strncat(ctx->result->unsupportedEntitySummary, line,
            sizeof(ctx->result->unsupportedEntitySummary) -
                strlen(ctx->result->unsupportedEntitySummary) - 1);
  }
}

static void sk_add_clamped_count(int *destination, unsigned long long value) {
  if (!destination || value == 0) {
    return;
  }
  const unsigned long long current = *destination > 0 ? (unsigned long long)*destination : 0;
  const unsigned long long next = current + value;
  *destination = next > 2147483647ULL ? 2147483647 : (int)next;
}

static bool sk_block_header_is_xref(const Dwg_Object_BLOCK_HEADER *header) {
  if (!header) {
    return false;
  }
  return header->blkisxref || header->is_xref_ref || header->is_xref_dep ||
         header->xrefoverlaid || header->xref_loaded ||
         (header->xref_pname && header->xref_pname[0]);
}

static void sk_record_block_header_metadata(SKParseContext *ctx,
                                            const Dwg_Object *blockHeaderObject) {
  if (!ctx || !ctx->result || !blockHeaderObject ||
      blockHeaderObject->fixedtype != DWG_TYPE_BLOCK_HEADER ||
      !blockHeaderObject->tio.object ||
      !blockHeaderObject->tio.object->tio.BLOCK_HEADER) {
    return;
  }
  const Dwg_Object_BLOCK_HEADER *header =
      blockHeaderObject->tio.object->tio.BLOCK_HEADER;
  if (sk_block_header_is_xref(header)) {
    ctx->result->blockXrefCount += 1;
  }
  if (header->anonymous) {
    ctx->result->blockAnonymousCount += 1;
  }
}

static void sk_append_count_summary(char *summary, size_t capacity,
                                    const char *label, int count);

static const Dwg_Object_BLOCK_HEADER *sk_block_header_from_object(
    const Dwg_Object *object) {
  if (!object || object->fixedtype != DWG_TYPE_BLOCK_HEADER ||
      !object->tio.object || !object->tio.object->tio.BLOCK_HEADER) {
    return NULL;
  }
  return object->tio.object->tio.BLOCK_HEADER;
}

static int sk_clamped_reference_count_from_block_header(
    const Dwg_Object_BLOCK_HEADER *header) {
  if (!header) {
    return 0;
  }
  unsigned long long count = 0;
  if (header->num_inserts > 0) {
    count = (unsigned long long)header->num_inserts;
  } else if (header->used > 0) {
    count = (unsigned long long)header->used;
  }
  return count > 2147483647ULL ? 2147483647 : (int)count;
}

static void sk_write_xref_reference_summary(SKCADParseResult *result) {
  if (!result) {
    return;
  }

  char summary[sizeof(result->xrefReferenceSummary)];
  summary[0] = '\0';
  sk_append_count_summary(summary, sizeof(summary), "XREF",
                          result->xrefReferenceCount);
  int loadedCount = 0;
  int overlayCount = 0;
  int pathCount = 0;
  for (int index = 0; index < result->xrefReferenceCount; index++) {
    const SKCADXrefReference *xref = &result->xrefs[index];
    if (xref->isLoaded || xref->isResolvedInDWG) {
      loadedCount += 1;
    }
    if (xref->isOverlay) {
      overlayCount += 1;
    }
    if (xref->savedPath && xref->savedPath[0]) {
      pathCount += 1;
    }
  }
  sk_append_count_summary(summary, sizeof(summary), "DWG已加载", loadedCount);
  sk_append_count_summary(summary, sizeof(summary), "overlay", overlayCount);
  sk_append_count_summary(summary, sizeof(summary), "带路径", pathCount);
  sk_copy_fixed(result->xrefReferenceSummary,
                sizeof(result->xrefReferenceSummary), summary);
}

static void sk_collect_xref_references(SKParseContext *ctx) {
  if (!ctx || !ctx->result || !ctx->dwg || !ctx->dwg->object ||
      ctx->dwg->num_objects == 0) {
    return;
  }

  int count = 0;
  for (BITCODE_BL index = 0; index < ctx->dwg->num_objects; index++) {
    const Dwg_Object_BLOCK_HEADER *header =
        sk_block_header_from_object(&ctx->dwg->object[index]);
    if (sk_block_header_is_xref(header)) {
      count += 1;
    }
  }

  ctx->result->xrefReferenceCount = count;
  ctx->result->blockXrefCount = count;
  if (count <= 0) {
    sk_write_xref_reference_summary(ctx->result);
    return;
  }

  ctx->result->xrefs =
      (SKCADXrefReference *)calloc((size_t)count, sizeof(SKCADXrefReference));
  if (!ctx->result->xrefs) {
    ctx->result->xrefReferenceCount = 0;
    ctx->result->blockXrefCount = 0;
    sk_set_error(ctx->result, "DWG XREF 清单内存分配失败。");
    return;
  }

  int cursor = 0;
  for (BITCODE_BL index = 0; index < ctx->dwg->num_objects && cursor < count; index++) {
    const Dwg_Object_BLOCK_HEADER *header =
        sk_block_header_from_object(&ctx->dwg->object[index]);
    if (!sk_block_header_is_xref(header)) {
      continue;
    }

    SKCADXrefReference *xref = &ctx->result->xrefs[cursor++];
    xref->name = sk_utf8_copy(header->name, sk_context_codepage(ctx));
    xref->savedPath = sk_utf8_copy(header->xref_pname, sk_context_codepage(ctx));
    xref->isOverlay = header->xrefoverlaid ? 1 : 0;
    xref->isLoaded = header->xref_loaded ? 1 : 0;
    xref->isResolvedInDWG = header->is_xref_resolved ? 1 : 0;
    xref->referenceCount = sk_clamped_reference_count_from_block_header(header);
  }

  sk_write_xref_reference_summary(ctx->result);
}

static void sk_append_count_summary(char *summary, size_t capacity,
                                    const char *label, int count) {
  if (!summary || capacity == 0 || !label || count <= 0) {
    return;
  }
  const size_t used = strlen(summary);
  if (used + 1 >= capacity) {
    return;
  }
  char item[64];
  snprintf(item, sizeof(item), "%s:%d", label, count);
  if (summary[0]) {
    strncat(summary, ", ", capacity - strlen(summary) - 1);
    if (strlen(summary) + 1 >= capacity) {
      return;
    }
  }
  strncat(summary, item, capacity - strlen(summary) - 1);
}

static void sk_write_block_reference_summary(SKCADParseResult *result) {
  if (!result) {
    return;
  }
  char summary[sizeof(result->blockReferenceSummary)];
  summary[0] = '\0';
  sk_append_count_summary(summary, sizeof(summary), "INSERT",
                          result->blockInsertCount);
  sk_append_count_summary(summary, sizeof(summary), "MINSERT",
                          result->blockMInsertCount);
  sk_append_count_summary(summary, sizeof(summary), "展开",
                          result->blockExpandedCount);
  sk_append_count_summary(summary, sizeof(summary), "属性",
                          result->blockAttributeCount);
  sk_append_count_summary(summary, sizeof(summary), "属性定义",
                          result->blockAttdefCount);
  sk_append_count_summary(summary, sizeof(summary), "外部参照",
                          result->blockXrefCount);
  sk_append_count_summary(summary, sizeof(summary), "匿名块",
                          result->blockAnonymousCount);
  sk_append_count_summary(summary, sizeof(summary), "缺失块",
                          result->blockUnresolvedCount);
  sk_append_count_summary(summary, sizeof(summary), "递归跳过",
                          result->blockRecursiveSkipCount);
  sk_append_count_summary(summary, sizeof(summary), "层级过深",
                          result->blockDepthSkipCount);
  sk_append_count_summary(summary, sizeof(summary), "动态块代理",
                          result->blockDynamicProxyCount);
  sk_append_count_summary(summary, sizeof(summary), "代理对象",
                          result->proxyObjectCount);
  sk_copy_fixed(result->blockReferenceSummary,
                sizeof(result->blockReferenceSummary), summary);
}

static bool sk_append_line_kind(SKParseContext *ctx, SKAffineTransform2D transform,
                                double x1, double y1, double x2, double y2,
                                SKStrokeStyle style, const char *layerName,
                                SKCADPrimitiveKind kind) {
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = kind;
  primitive->start = sk_apply_point(transform, x1, y1);
  primitive->end = sk_apply_point(transform, x2, y2);
  primitive->layerName = sk_context_utf8_copy(ctx, layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  return true;
}

static void sk_point_buffer_free(SKPointBuffer *buffer) {
  if (!buffer) {
    return;
  }
  free(buffer->points);
  buffer->points = NULL;
  buffer->count = 0;
  buffer->capacity = 0;
}

static bool sk_point_buffer_append(SKPointBuffer *buffer, double x, double y) {
  if (!buffer || !isfinite(x) || !isfinite(y)) {
    return true;
  }
  if (buffer->count >= buffer->capacity) {
    int nextCapacity = buffer->capacity > 0 ? buffer->capacity * 2 : 16;
    if (nextCapacity < buffer->count + 1) {
      nextCapacity = buffer->count + 1;
    }
    SKCADPoint *next =
        (SKCADPoint *)realloc(buffer->points, (size_t)nextCapacity * sizeof(SKCADPoint));
    if (!next) {
      return false;
    }
    buffer->points = next;
    buffer->capacity = nextCapacity;
  }
  buffer->points[buffer->count].x = x;
  buffer->points[buffer->count].y = y;
  buffer->count += 1;
  return true;
}

static bool sk_point_buffer_close(SKPointBuffer *buffer) {
  if (!buffer || buffer->count < 3) {
    return true;
  }
  const SKCADPoint first = buffer->points[0];
  const SKCADPoint last = buffer->points[buffer->count - 1];
  if (fabs(first.x - last.x) <= 1e-9 && fabs(first.y - last.y) <= 1e-9) {
    return true;
  }
  return sk_point_buffer_append(buffer, first.x, first.y);
}

static bool sk_point_buffer_append_bulge(SKPointBuffer *buffer,
                                         double x1, double y1,
                                         double x2, double y2,
                                         double bulge) {
  if (!isfinite(bulge) || fabs(bulge) <= 1e-9) {
    return sk_point_buffer_append(buffer, x2, y2);
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
  double span = endAngle - startAngle;
  if (bulge > 0.0) {
    while (span < 0.0) {
      span += M_PI * 2.0;
    }
  } else {
    while (span > 0.0) {
      span -= M_PI * 2.0;
    }
  }

  const int segments = (int)fmin(96.0, fmax(6.0, ceil(fabs(span) / (M_PI / 24.0))));
  for (int index = 1; index <= segments; index++) {
    const double t = (double)index / (double)segments;
    const double angle = startAngle + span * t;
    if (!sk_point_buffer_append(buffer, cx + cos(angle) * radius,
                                cy + sin(angle) * radius)) {
      return false;
    }
  }
  return true;
}

static bool sk_append_source_polyline_kind(SKParseContext *ctx,
                                           SKAffineTransform2D transform,
                                           const SKCADPoint *sourcePoints,
                                           int pointCount,
                                           SKStrokeStyle style,
                                           const char *layerName,
                                           SKCADPrimitiveKind kind) {
  if (!ctx || !ctx->result || !sourcePoints || pointCount < 2) {
    return true;
  }
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  const unsigned long long pointBytes =
      (unsigned long long)pointCount * sizeof(SKCADPoint);
  if (ctx->result->estimatedPrimitiveMemory + pointBytes > SK_MAX_PRIMITIVE_BUFFER_BYTES) {
    sk_set_error(ctx->result,
                 "DWG 多点几何超过预览内存预算（上限 %.1f MB），已停止解析。",
                 (double)SK_MAX_PRIMITIVE_BUFFER_BYTES / 1024.0 / 1024.0);
    return false;
  }

  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->points = (SKCADPoint *)calloc((size_t)pointCount, sizeof(SKCADPoint));
  if (!primitive->points) {
    ctx->result->primitiveCount -= 1;
    sk_set_error(ctx->result, "DWG 多点几何内存分配失败。");
    return false;
  }

  primitive->kind = kind;
  primitive->pointCount = pointCount;
  for (int index = 0; index < pointCount; index++) {
    primitive->points[index] =
        sk_apply_point(transform, sourcePoints[index].x, sourcePoints[index].y);
  }
  primitive->start = primitive->points[0];
  primitive->end = primitive->points[pointCount - 1];
  primitive->center = primitive->points[pointCount / 2];
  primitive->layerName = sk_context_utf8_copy(ctx, layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  ctx->result->estimatedPrimitiveMemory += pointBytes;
  return true;
}

static bool sk_append_line(SKParseContext *ctx, SKAffineTransform2D transform,
                           double x1, double y1, double x2, double y2,
                           SKStrokeStyle style, const char *layerName) {
  return sk_append_line_kind(ctx, transform, x1, y1, x2, y2, style, layerName,
                             SKCADPrimitiveLine);
}

static bool sk_append_arc_kind(SKParseContext *ctx, SKAffineTransform2D transform,
                               double cx, double cy, double radius,
                               double startAngle, double endAngle,
                               SKStrokeStyle style, const char *layerName,
                               SKCADPrimitiveKind kind) {
  if (!isfinite(radius) || radius <= 0.0) {
    return true;
  }
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = kind;
  primitive->center = sk_apply_point(transform, cx, cy);
  primitive->radius = radius * sk_effective_scale(transform);
  primitive->startAngle = startAngle + sk_effective_rotation(transform);
  primitive->endAngle = endAngle + sk_effective_rotation(transform);
  primitive->layerName = sk_context_utf8_copy(ctx, layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  return true;
}

static bool sk_append_arc(SKParseContext *ctx, SKAffineTransform2D transform,
                          double cx, double cy, double radius, double startAngle,
                          double endAngle, SKStrokeStyle style,
                          const char *layerName) {
  return sk_append_arc_kind(ctx, transform, cx, cy, radius, startAngle, endAngle,
                            style, layerName, SKCADPrimitiveArc);
}

static bool sk_append_circle_kind(SKParseContext *ctx, SKAffineTransform2D transform,
                                  double cx, double cy, double radius,
                                  SKStrokeStyle style, const char *layerName,
                                  SKCADPrimitiveKind kind) {
  if (!isfinite(radius) || radius <= 0.0) {
    return true;
  }
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = kind;
  primitive->center = sk_apply_point(transform, cx, cy);
  primitive->radius = radius * sk_effective_scale(transform);
  primitive->layerName = sk_context_utf8_copy(ctx, layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  return true;
}

static bool sk_append_circle(SKParseContext *ctx, SKAffineTransform2D transform,
                             double cx, double cy, double radius,
                             SKStrokeStyle style, const char *layerName) {
  return sk_append_circle_kind(ctx, transform, cx, cy, radius, style, layerName,
                               SKCADPrimitiveCircle);
}

static bool sk_append_text_kind(SKParseContext *ctx, SKAffineTransform2D transform,
                                double x, double y, double height,
                                double rotation, const char *text,
                                SKStrokeStyle style, const char *layerName,
                                const Dwg_Object_STYLE *textStyle,
                                SKCADPrimitiveKind kind) {
  if (!text || !text[0]) {
    return true;
  }
  if (ctx && (ctx->parseOptions & SKCADParseOptionSkipText) != 0) {
    return true;
  }
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = kind;
  primitive->start = sk_apply_point(transform, x, y);
  primitive->textHeight =
      (height > 0.0 && isfinite(height)) ? height * sk_effective_scale(transform)
                                         : 2.0;
  primitive->textRotation = rotation + sk_effective_rotation(transform);
  primitive->layerName = sk_context_utf8_copy(ctx, layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  primitive->rawTextBytesHex = sk_hex_copy(text);
  char *decodedText =
      sk_context_utf8_copy_with_codepage(ctx, text, &primitive->chosenCodepage);
  primitive->text = sk_normalize_cad_text(decodedText);
  free(decodedText);
  if (textStyle) {
    primitive->textStyleName = sk_context_utf8_copy(ctx, textStyle->name);
    primitive->fontFile = sk_context_utf8_copy(ctx, textStyle->font_file);
    primitive->bigFontFile = sk_context_utf8_copy(ctx, textStyle->bigfont_file);
  }
  if (!primitive->text) {
    primitive->text = NULL;
  } else if (ctx->result) {
    ctx->result->textPrimitiveCount += 1;
    if (sk_text_looks_latin1_mojibake(primitive->text)) {
      ctx->result->mojibakeTextCount += 1;
    }
    if (sk_text_looks_suspicious(primitive->text)) {
      ctx->result->suspiciousTextCount += 1;
    }
  }
  return true;
}

static bool sk_append_text(SKParseContext *ctx, SKAffineTransform2D transform,
                           double x, double y, double height, double rotation,
                           const char *text, SKStrokeStyle style,
                           const char *layerName,
                           const Dwg_Object_STYLE *textStyle) {
  return sk_append_text_kind(ctx, transform, x, y, height, rotation, text, style,
                             layerName, textStyle, SKCADPrimitiveText);
}

static bool sk_append_lwpolyline(SKParseContext *ctx,
                                 const Dwg_Entity_LWPOLYLINE *lwpolyline,
                                 SKAffineTransform2D transform,
                                 SKStrokeStyle style,
                                 const char *layerName,
                                 SKCADPrimitiveKind kind) {
  if (!lwpolyline || lwpolyline->num_points < 2 || !lwpolyline->points) {
    return true;
  }
  SKPointBuffer buffer = {0};
  const BITCODE_2RD first = lwpolyline->points[0];
  if (!sk_point_buffer_append(&buffer, first.x, first.y)) {
    sk_point_buffer_free(&buffer);
    sk_set_error(ctx->result, "DWG LWPOLYLINE 点集内存分配失败。");
    return false;
  }
  for (BITCODE_BL index = 1; index < lwpolyline->num_points; index++) {
    const BITCODE_2RD p0 = lwpolyline->points[index - 1];
    const BITCODE_2RD p1 = lwpolyline->points[index];
    const double bulge =
        (lwpolyline->bulges && index - 1 < lwpolyline->num_bulges)
            ? lwpolyline->bulges[index - 1]
            : 0.0;
    if (!sk_point_buffer_append_bulge(&buffer, p0.x, p0.y, p1.x, p1.y, bulge)) {
      sk_point_buffer_free(&buffer);
      sk_set_error(ctx->result, "DWG LWPOLYLINE 点集内存分配失败。");
      return false;
    }
  }
  if ((lwpolyline->flag & 512) == 512) {
    const BITCODE_2RD last = lwpolyline->points[lwpolyline->num_points - 1];
    const double closingBulge =
        (lwpolyline->bulges && lwpolyline->num_points - 1 < lwpolyline->num_bulges)
            ? lwpolyline->bulges[lwpolyline->num_points - 1]
            : 0.0;
    if (!sk_point_buffer_append_bulge(&buffer, last.x, last.y, first.x, first.y,
                                      closingBulge)) {
      sk_point_buffer_free(&buffer);
      sk_set_error(ctx->result, "DWG LWPOLYLINE 闭合点集内存分配失败。");
      return false;
    }
  }
  const bool appended = sk_append_source_polyline_kind(ctx, transform, buffer.points,
                                                       buffer.count, style, layerName, kind);
  sk_point_buffer_free(&buffer);
  return appended;
}

static bool sk_append_polyline_from_subentities(SKParseContext *ctx,
                                                const Dwg_Object *polylineObject,
                                                SKAffineTransform2D transform,
                                                bool closed,
                                                SKStrokeStyle style,
                                                const char *layerName,
                                                SKCADPrimitiveKind kind) {
  if (!polylineObject) {
    return true;
  }
  Dwg_Object *subentity = get_first_owned_subentity(polylineObject);
  SKPointBuffer buffer = {0};

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
    case DWG_TYPE_VERTEX_PFACE:
    case DWG_TYPE_VERTEX_PFACE_FACE: {
      ctx->result->unsupportedEntityCount += 1;
      sk_track_unsupported(ctx, subentity->fixedtype);
      break;
    }
    case DWG_TYPE_SEQEND:
      subentity = NULL;
      continue;
    default:
      break;
    }

    if (didAppendPoint) {
      if (!sk_point_buffer_append(&buffer, x, y)) {
        sk_point_buffer_free(&buffer);
        sk_set_error(ctx->result, "DWG POLYLINE 点集内存分配失败。");
        return false;
      }
    }

    Dwg_Object *next = get_next_owned_subentity(polylineObject, subentity);
    if (!next || next == subentity) {
      break;
    }
    subentity = next;
  }

  if (closed) {
    if (!sk_point_buffer_close(&buffer)) {
      sk_point_buffer_free(&buffer);
      sk_set_error(ctx->result, "DWG POLYLINE 闭合点集内存分配失败。");
      return false;
    }
  }
  const bool appended = sk_append_source_polyline_kind(ctx, transform, buffer.points,
                                                       buffer.count, style, layerName, kind);
  sk_point_buffer_free(&buffer);
  return appended;
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
      if (!sk_append_line_kind(ctx, transform, prevX, prevY, worldX, worldY,
                               style, layerName, SKCADPrimitiveEllipse)) {
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
                                    SKStrokeStyle style, const char *layerName,
                                    SKCADPrimitiveKind kind) {
  if (!isfinite(x1) || !isfinite(y1) || !isfinite(x2) || !isfinite(y2)) {
    return true;
  }
  if (fabs(x1 - x2) <= 1e-9 && fabs(y1 - y2) <= 1e-9) {
    return true;
  }
  return sk_append_line_kind(ctx, transform, x1, y1, x2, y2, style, layerName,
                             kind);
}

static bool sk_append_attrib_like_text(SKParseContext *ctx, SKAffineTransform2D transform,
                                       double x, double y, double height, double rotation,
                                       const char *textValue, SKStrokeStyle style,
                                       const char *layerName,
                                       const Dwg_Object_STYLE *textStyle) {
  if (!textValue || !textValue[0]) {
    return true;
  }
  return sk_append_text_kind(ctx, transform, x, y, height, rotation, textValue,
                             style, layerName, textStyle, SKCADPrimitiveText);
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
  return sk_append_text_kind(ctx, transform, textX, textY, 2.2, textRotation,
                             displayText, style, layerName, NULL,
                             SKCADPrimitiveDimension);
}

static bool sk_append_solid_outline(SKParseContext *ctx, SKAffineTransform2D transform,
                                    double x1, double y1, double x2, double y2,
                                    double x3, double y3, double x4, double y4,
                                    SKStrokeStyle style, const char *layerName) {
  SKCADPoint points[5] = {
      {x1, y1},
      {x2, y2},
      {x3, y3},
      {x4, y4},
      {x1, y1},
  };
  return sk_append_source_polyline_kind(ctx, transform, points, 5, style,
                                        layerName, SKCADPrimitivePolyline);
}

static bool sk_append_dimension_linear_like(SKParseContext *ctx, SKAffineTransform2D transform,
                                            const Dwg_Entity_DIMENSION_LINEAR *dim,
                                            SKStrokeStyle style, const char *layerName) {
  if (!dim) {
    return true;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline1_pt.x, dim->xline1_pt.y,
                               dim->xline2_pt.x, dim->xline2_pt.y, style,
                               layerName, SKCADPrimitiveDimension)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline1_pt.x, dim->xline1_pt.y,
                               dim->def_pt.x, dim->def_pt.y, style, layerName,
                               SKCADPrimitiveDimension)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline2_pt.x, dim->xline2_pt.y,
                               dim->def_pt.x, dim->def_pt.y, style, layerName,
                               SKCADPrimitiveDimension)) {
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
                               dim->xline2_pt.x, dim->xline2_pt.y, style,
                               layerName, SKCADPrimitiveDimension)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline1_pt.x, dim->xline1_pt.y,
                               dim->def_pt.x, dim->def_pt.y, style, layerName,
                               SKCADPrimitiveDimension)) {
    return false;
  }
  if (!sk_append_line_if_valid(ctx, transform, dim->xline2_pt.x, dim->xline2_pt.y,
                               dim->def_pt.x, dim->def_pt.y, style, layerName,
                               SKCADPrimitiveDimension)) {
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
  return sk_append_arc_kind(ctx, transform, cx, cy, radius, startAngle, endAngle,
                            style, layerName, SKCADPrimitiveHatch);
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
      if (!sk_append_line_if_valid(ctx, transform, prevX, prevY, worldX, worldY,
                                   style, layerName, SKCADPrimitiveHatch)) {
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
    return sk_append_line_if_valid(ctx, transform, x1, y1, x2, y2, style,
                                   layerName, SKCADPrimitiveHatch);
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
  return sk_append_arc_kind(ctx, transform, cx, cy, radius, startAngle, endAngle,
                            style, layerName, SKCADPrimitiveHatch);
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
      if (!path->bulges_present) {
        SKPointBuffer buffer = {0};
        for (BITCODE_BL index = 0; index < count; index++) {
          const Dwg_HATCH_PolylinePath *point = &path->polyline_paths[index];
          if (!sk_point_buffer_append(&buffer, point->point.x, point->point.y)) {
            sk_point_buffer_free(&buffer);
            sk_set_error(ctx->result, "DWG HATCH 点集内存分配失败。");
            return false;
          }
        }
        if (path->closed && !sk_point_buffer_close(&buffer)) {
          sk_point_buffer_free(&buffer);
          sk_set_error(ctx->result, "DWG HATCH 闭合点集内存分配失败。");
          return false;
        }
        const bool appended = sk_append_source_polyline_kind(
            ctx, transform, buffer.points, buffer.count, style, layerName,
            SKCADPrimitiveHatch);
        sk_point_buffer_free(&buffer);
        if (!appended) {
          return false;
        }
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
                                     seg->second_endpoint.x, seg->second_endpoint.y,
                                     style, layerName, SKCADPrimitiveHatch)) {
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
            if (!sk_append_line_if_valid(ctx, transform, p0.x, p0.y, p1.x, p1.y,
                                         style, layerName,
                                         SKCADPrimitiveHatch)) {
              return false;
            }
          }
        } else if (seg->control_points && seg->num_control_points > 1) {
          for (BITCODE_BL cpIndex = 1; cpIndex < seg->num_control_points; cpIndex++) {
            const BITCODE_2RD p0 = seg->control_points[cpIndex - 1].point;
            const BITCODE_2RD p1 = seg->control_points[cpIndex].point;
            if (!sk_append_line_if_valid(ctx, transform, p0.x, p0.y, p1.x, p1.y,
                                         style, layerName,
                                         SKCADPrimitiveHatch)) {
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
  SKPointBuffer buffer = {0};
  for (BITCODE_BL index = 0; index < leader->num_points; index++) {
    const BITCODE_3DPOINT point = leader->points[index];
    if (!sk_point_buffer_append(&buffer, point.x, point.y)) {
      sk_point_buffer_free(&buffer);
      sk_set_error(ctx->result, "DWG LEADER 点集内存分配失败。");
      return false;
    }
  }
  const bool appended = sk_append_source_polyline_kind(ctx, transform, buffer.points,
                                                       buffer.count, style, layerName,
                                                       SKCADPrimitiveLeader);
  sk_point_buffer_free(&buffer);
  return appended;
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
        SKPointBuffer buffer = {0};
        for (BITCODE_BL pointIndex = 0; pointIndex < line->num_points; pointIndex++) {
          const BITCODE_3DPOINT point = line->points[pointIndex];
          if (!sk_point_buffer_append(&buffer, point.x, point.y)) {
            sk_point_buffer_free(&buffer);
            sk_set_error(ctx->result, "DWG MLEADER 点集内存分配失败。");
            return false;
          }
        }
        const bool appended = sk_append_source_polyline_kind(
            ctx, transform, buffer.points, buffer.count, style, layerName,
            SKCADPrimitiveLeader);
        sk_point_buffer_free(&buffer);
        if (!appended) {
            return false;
        }
      }
    }
  }
  if (leader->ctx.has_content_txt) {
    const Dwg_MLEADER_Content_MText *txt = &leader->ctx.content.txt;
    if (!sk_append_text_kind(ctx, transform, txt->location.x, txt->location.y,
                             leader->ctx.text_height > 0.0 ? leader->ctx.text_height : 2.2,
                             txt->rotation, txt->default_text, style, layerName,
                             NULL, SKCADPrimitiveLeader)) {
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
                                        const char *layerName,
                                        SKCADPrimitiveKind kind) {
  if (num_clip_verts > 1 && clip_verts) {
    SKPointBuffer buffer = {0};
    for (BITCODE_BL index = 0; index < num_clip_verts; index++) {
      const BITCODE_2RD p0c = clip_verts[index];
      const double x0 = pt0.x + uvec.x * p0c.x + vvec.x * p0c.y;
      const double y0 = pt0.y + uvec.y * p0c.x + vvec.y * p0c.y;
      if (!sk_point_buffer_append(&buffer, x0, y0)) {
        sk_point_buffer_free(&buffer);
        sk_set_error(ctx->result, "DWG 图像边界点集内存分配失败。");
        return false;
      }
    }
    if (!sk_point_buffer_close(&buffer)) {
      sk_point_buffer_free(&buffer);
      sk_set_error(ctx->result, "DWG 图像边界闭合点集内存分配失败。");
      return false;
    }
    const bool appended = sk_append_source_polyline_kind(ctx, transform, buffer.points,
                                                         buffer.count, style, layerName, kind);
    sk_point_buffer_free(&buffer);
    return appended;
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
  SKCADPoint points[5] = {
      {ax, ay},
      {bx, by},
      {cx, cy},
      {dx, dy},
      {ax, ay},
  };
  return sk_append_source_polyline_kind(ctx, transform, points, 5, style, layerName, kind);
}

static bool sk_append_marker(SKParseContext *ctx, SKAffineTransform2D transform,
                             double x, double y, SKStrokeStyle style,
                             const char *layerName, SKCADPrimitiveKind kind) {
  if (!sk_ensure_capacity(ctx, 1)) {
    return false;
  }
  SKCADPrimitive *primitive =
      &ctx->result->primitives[ctx->result->primitiveCount++];
  memset(primitive, 0, sizeof(*primitive));
  primitive->kind = kind;
  primitive->start = sk_apply_point(transform, x, y);
  primitive->end = primitive->start;
  primitive->center = primitive->start;
  primitive->layerName = sk_context_utf8_copy(ctx, layerName ? layerName : "0");
  primitive->strokeRGB = style.rgb;
  primitive->strokeWidth = style.width;
  return true;
}

static SKCADPoint sk_block_base_point(const Dwg_Object *blockHeaderObject) {
  SKCADPoint point;
  point.x = 0.0;
  point.y = 0.0;
  if (!blockHeaderObject ||
      blockHeaderObject->fixedtype != DWG_TYPE_BLOCK_HEADER ||
      !blockHeaderObject->tio.object ||
      !blockHeaderObject->tio.object->tio.BLOCK_HEADER) {
    return point;
  }
  const Dwg_Object_BLOCK_HEADER *header =
      blockHeaderObject->tio.object->tio.BLOCK_HEADER;
  if (isfinite(header->base_pt.x) && isfinite(header->base_pt.y)) {
    point.x = header->base_pt.x;
    point.y = header->base_pt.y;
  }
  return point;
}

static SKAffineTransform2D sk_insert_transform(double tx, double ty, double sx,
                                               double sy, double rotation,
                                               SKCADPoint blockBasePoint) {
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
  out.tx = tx - (out.a * blockBasePoint.x + out.b * blockBasePoint.y);
  out.ty = ty - (out.c * blockBasePoint.x + out.d * blockBasePoint.y);
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
                                   const Dwg_Object **stack, int stackCount,
                                   const SKStrokeStyle *blockStyle,
                                   const char *blockLayerName);

static bool sk_parse_block_entities(SKParseContext *ctx,
                                    const Dwg_Object *blockHeaderObject,
                                    SKAffineTransform2D transform,
                                    const Dwg_Object **stack, int stackCount,
                                    const SKStrokeStyle *blockStyle,
                                    const char *blockLayerName) {
  if (!ctx || !blockHeaderObject ||
      blockHeaderObject->fixedtype != DWG_TYPE_BLOCK_HEADER) {
    return true;
  }

  if (sk_is_in_stack(blockHeaderObject, stack, stackCount)) {
    ctx->result->unsupportedEntityCount += 1;
    ctx->result->blockRecursiveSkipCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_INSERT);
    return true;
  }

  if (stackCount >= SK_MAX_RECURSION_DEPTH) {
    ctx->result->blockDepthSkipCount += 1;
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
                                stackCount + 1, blockStyle, blockLayerName)) {
      return false;
    }
    entity = get_next_owned_entity(blockHeaderObject, entity);
  }
  return true;
}

static bool sk_parse_insert_owned_attribs(SKParseContext *ctx,
                                          const Dwg_Object *insertObject,
                                          SKAffineTransform2D transform,
                                          const Dwg_Object **stack,
                                          int stackCount,
                                          const SKStrokeStyle *blockStyle,
                                          const char *blockLayerName) {
  if (!ctx || !insertObject) {
    return true;
  }

  Dwg_Object *subentity = get_first_owned_subentity(insertObject);
  while (subentity) {
    if (subentity->fixedtype == DWG_TYPE_ATTRIB) {
      if (!sk_parse_entity_object(ctx, subentity, transform, stack, stackCount,
                                  blockStyle, blockLayerName)) {
        return false;
      }
    }
    subentity = get_next_owned_subentity(insertObject, subentity);
  }
  return true;
}

static bool sk_parse_insert_entity(SKParseContext *ctx,
                                   const Dwg_Object *insertObject,
                                   const Dwg_Entity_INSERT *insertEntity,
                                   SKAffineTransform2D transform,
                                   const Dwg_Object **stack, int stackCount,
                                   const SKStrokeStyle *insertStyle,
                                   const char *insertLayerName) {
  if (ctx && ctx->result) {
    ctx->result->blockInsertCount += 1;
  }
  if (!insertEntity || !insertEntity->block_header) {
    ctx->result->unsupportedEntityCount += 1;
    ctx->result->blockUnresolvedCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_INSERT);
    return true;
  }
  if (ctx && ctx->result && insertEntity->has_attribs) {
    sk_add_clamped_count(&ctx->result->blockAttributeCount,
                         (unsigned long long)insertEntity->num_owned);
  }

  Dwg_Object *blockHeaderObject =
      insertEntity->block_header->obj
          ? insertEntity->block_header->obj
          : dwg_ref_object(ctx->dwg, insertEntity->block_header);
  if (!blockHeaderObject || blockHeaderObject->fixedtype != DWG_TYPE_BLOCK_HEADER) {
    ctx->result->unsupportedEntityCount += 1;
    ctx->result->blockUnresolvedCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_INSERT);
    return true;
  }
  sk_record_block_header_metadata(ctx, blockHeaderObject);

  const double sx = insertEntity->scale.x;
  const double sy = insertEntity->scale.y;
  const SKCADPoint blockBasePoint = sk_block_base_point(blockHeaderObject);
  const SKAffineTransform2D local = sk_insert_transform(
      insertEntity->ins_pt.x, insertEntity->ins_pt.y, sx, sy,
      insertEntity->rotation, blockBasePoint);
  const SKAffineTransform2D composed = sk_compose_transform(transform, local);

  const bool parsed = sk_parse_block_entities(ctx, blockHeaderObject, composed,
                                              stack, stackCount, insertStyle,
                                              insertLayerName);
  if (!parsed) {
    return false;
  }
  if (!sk_parse_insert_owned_attribs(ctx, insertObject, transform, stack,
                                     stackCount, insertStyle,
                                     insertLayerName)) {
    return false;
  }
  if (ctx && ctx->result) {
    ctx->result->blockExpandedCount += 1;
  }
  return true;
}

static bool sk_parse_minsert_entity(SKParseContext *ctx,
                                    const Dwg_Object *insertObject,
                                    const Dwg_Entity_MINSERT *insertEntity,
                                    SKAffineTransform2D transform,
                                    const Dwg_Object **stack, int stackCount,
                                    const SKStrokeStyle *insertStyle,
                                    const char *insertLayerName) {
  if (ctx && ctx->result) {
    ctx->result->blockMInsertCount += 1;
  }
  if (!insertEntity || !insertEntity->block_header) {
    ctx->result->unsupportedEntityCount += 1;
    ctx->result->blockUnresolvedCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_MINSERT);
    return true;
  }
  if (ctx && ctx->result && insertEntity->has_attribs) {
    sk_add_clamped_count(&ctx->result->blockAttributeCount,
                         (unsigned long long)insertEntity->num_owned);
  }

  Dwg_Object *blockHeaderObject =
      insertEntity->block_header->obj
          ? insertEntity->block_header->obj
          : dwg_ref_object(ctx->dwg, insertEntity->block_header);
  if (!blockHeaderObject || blockHeaderObject->fixedtype != DWG_TYPE_BLOCK_HEADER) {
    ctx->result->unsupportedEntityCount += 1;
    ctx->result->blockUnresolvedCount += 1;
    sk_track_unsupported(ctx, DWG_TYPE_MINSERT);
    return true;
  }
  sk_record_block_header_metadata(ctx, blockHeaderObject);

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
  const SKCADPoint blockBasePoint = sk_block_base_point(blockHeaderObject);
  const SKAffineTransform2D baseTransform = sk_insert_transform(
      insertEntity->ins_pt.x, insertEntity->ins_pt.y, baseScaleX, baseScaleY,
      insertEntity->rotation, blockBasePoint);
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
                                   stackCount, insertStyle, insertLayerName)) {
        return false;
      }
      if (!sk_parse_insert_owned_attribs(ctx, insertObject, finalTransform, stack,
                                         stackCount, insertStyle,
                                         insertLayerName)) {
        return false;
      }
      if (ctx && ctx->result) {
        ctx->result->blockExpandedCount += 1;
      }
    }
  }

  return true;
}

static bool sk_parse_entity_object(SKParseContext *ctx, const Dwg_Object *object,
                                   SKAffineTransform2D transform,
                                   const Dwg_Object **stack, int stackCount,
                                   const SKStrokeStyle *blockStyle,
                                   const char *blockLayerName) {
  if (!ctx || !object || object->supertype != DWG_SUPERTYPE_ENTITY ||
      !object->tio.entity) {
    return true;
  }

  const SKStrokeStyle style = sk_style_from_entity(object->tio.entity, blockStyle);
  const char *layerName =
      sk_layer_name_from_entity(object->tio.entity, blockLayerName);

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
                          layerName, sk_text_style_from_ref(ctx, text->style));
  }

  case DWG_TYPE_MTEXT: {
    const Dwg_Entity_MTEXT *text = object->tio.entity->tio.MTEXT;
    if (!text) {
      return true;
    }
    const double rotation = atan2(text->x_axis_dir.y, text->x_axis_dir.x);
    return sk_append_text_kind(ctx, transform, text->ins_pt.x, text->ins_pt.y,
                               text->text_height, rotation, text->text, style,
                               layerName, sk_text_style_from_ref(ctx, text->style),
                               SKCADPrimitiveMText);
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
        layerName,
        sk_text_style_from_ref(ctx, attrib->style));
  }

  case DWG_TYPE_ATTDEF: {
    if (ctx->result) {
      ctx->result->blockAttdefCount += 1;
    }
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
        layerName,
        sk_text_style_from_ref(ctx, attdef->style));
  }

  case DWG_TYPE_LWPOLYLINE: {
    const Dwg_Entity_LWPOLYLINE *lwpolyline = object->tio.entity->tio.LWPOLYLINE;
    return sk_append_lwpolyline(ctx, lwpolyline, transform, style, layerName,
                                SKCADPrimitivePolyline);
  }

  case DWG_TYPE_POLYLINE_2D: {
    const Dwg_Entity_POLYLINE_2D *polyline = object->tio.entity->tio.POLYLINE_2D;
    const bool closed = polyline && ((polyline->flag & 1) == 1);
    return sk_append_polyline_from_subentities(ctx, object, transform, closed,
                                               style, layerName,
                                               SKCADPrimitivePolyline);
  }

  case DWG_TYPE_POLYLINE_3D: {
    ctx->result->unsupportedEntityCount += 1;
    sk_track_unsupported(ctx, object->fixedtype);
    return true;
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
    ctx->result->unsupportedEntityCount += 1;
    sk_track_unsupported(ctx, object->fixedtype);
    return true;
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
                                 dim->first_arc_pt.x, dim->first_arc_pt.y, style,
                                 layerName, SKCADPrimitiveDimension)) {
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
                                 dim->first_arc_pt.x, dim->first_arc_pt.y, style,
                                 layerName, SKCADPrimitiveDimension)) {
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
                                 dim->leader_endpt.x, dim->leader_endpt.y, style,
                                 layerName, SKCADPrimitiveDimension)) {
      return false;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->leader_endpt.x, dim->leader_endpt.y,
                                 dim->def_pt.x, dim->def_pt.y, style, layerName,
                                 SKCADPrimitiveDimension)) {
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
                                 dim->xline1_pt.x, dim->xline1_pt.y, style,
                                 layerName, SKCADPrimitiveDimension)) {
      return false;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->center_pt.x, dim->center_pt.y,
                                 dim->xline2_pt.x, dim->xline2_pt.y, style,
                                 layerName, SKCADPrimitiveDimension)) {
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
                                 dim->xline1end_pt.x, dim->xline1end_pt.y, style,
                                 layerName, SKCADPrimitiveDimension)) {
      return false;
    }
    if (!sk_append_line_if_valid(ctx, transform, dim->xline2start_pt.x, dim->xline2start_pt.y,
                                 dim->xline2end_pt.x, dim->xline2end_pt.y, style,
                                 layerName, SKCADPrimitiveDimension)) {
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
        layerName,
        SKCADPrimitiveImage);
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
        layerName,
        SKCADPrimitiveWipeout);
  }

  case DWG_TYPE_INSERT: {
    const Dwg_Entity_INSERT *insertEntity = object->tio.entity->tio.INSERT;
    if (insertEntity) {
      if (!sk_append_marker(ctx, transform, insertEntity->ins_pt.x,
                            insertEntity->ins_pt.y, style, layerName,
                            SKCADPrimitiveBlockRef)) {
        return false;
      }
    }
    return sk_parse_insert_entity(ctx, object, insertEntity, transform, stack,
                                  stackCount, &style, layerName);
  }

  case DWG_TYPE_MINSERT: {
    const Dwg_Entity_MINSERT *insertEntity = object->tio.entity->tio.MINSERT;
    if (insertEntity) {
      if (!sk_append_marker(ctx, transform, insertEntity->ins_pt.x,
                            insertEntity->ins_pt.y, style, layerName,
                            SKCADPrimitiveBlockRef)) {
        return false;
      }
    }
    return sk_parse_minsert_entity(ctx, object, insertEntity, transform, stack,
                                   stackCount, &style, layerName);
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
    if (object->fixedtype == DWG_TYPE_PROXY_ENTITY ||
        object->fixedtype == DWG_TYPE_PROXY_OBJECT ||
        object->fixedtype == DWG_TYPE_DYNAMICBLOCKPROXYNODE) {
      if (object->fixedtype == DWG_TYPE_DYNAMICBLOCKPROXYNODE) {
        ctx->result->blockDynamicProxyCount += 1;
      } else {
        ctx->result->proxyObjectCount += 1;
      }
      if (!sk_append_marker(ctx, transform, 0.0, 0.0, style, layerName,
                            SKCADPrimitiveUnknownProxy)) {
        return false;
      }
    }
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
    if (!sk_parse_block_entities(ctx, modelSpace, identity, NULL, 0, NULL, NULL)) {
      return false;
    }
  }

  if (paperSpace && paperSpace->fixedtype == DWG_TYPE_BLOCK_HEADER &&
      paperSpace != modelSpace) {
    parsedRoots += 1;
    if (!sk_parse_block_entities(ctx, paperSpace, identity, NULL, 0, NULL, NULL)) {
      return false;
    }
  }

  if (parsedRoots > 0 && ctx->result->primitiveCount > 0) {
    return true;
  }

  // Fallback: older/damaged DWG files can expose model/paper block headers while
  // losing the ownership chain to their child entities. In that case a root-only
  // pass produces no geometry even though drawable entities exist in the object
  // table, so do one conservative all-entity scan before reporting an empty file.
  for (BITCODE_BL index = 0; index < ctx->dwg->num_objects; index++) {
    const Dwg_Object *object = &ctx->dwg->object[index];
    if (!sk_parse_entity_object(ctx, object, identity, NULL, 0, NULL, NULL)) {
      return false;
    }
  }
  return true;
}

int sk_libredwg_parse_file(const char *path, SKCADParseResult *result) {
  return sk_libredwg_parse_file_with_options(path, 0, 0, result);
}

int sk_libredwg_parse_file_with_codepage(const char *path, int codepage_override,
                                         SKCADParseResult *result) {
  return sk_libredwg_parse_file_with_options(path, codepage_override, 0, result);
}

int sk_libredwg_parse_file_with_options(const char *path, int codepage_override,
                                        int parse_options,
                                        SKCADParseResult *result) {
  if (!result) {
    return 0;
  }
  memset(result, 0, sizeof(*result));
  sk_fill_budget_metadata(result);
  if (!path || !path[0]) {
    sk_set_error(result, "DWG 文件路径为空。");
    return 0;
  }

  Dwg_Data dwg;
  memset(&dwg, 0, sizeof(dwg));

  const int readStatus = dwg_read_file(path, &dwg);
  sk_fill_version_metadata(result, &dwg, readStatus);
  if (sk_read_status_blocks_geometry_parse(readStatus)) {
    sk_set_error(
        result,
        "LibreDWG 读取到严重 DWG 错误（错误码 %d），已停止原生解析以避免闪退。"
        "请检查原 DWG 是否损坏、是否包含大量代理/AEC/天正对象，或导出 CAD 诊断日志定位。",
        readStatus);
    dwg_free(&dwg);
    return 0;
  }

  if (dwg.num_objects > (BITCODE_BL)SK_MAX_DWG_OBJECT_COUNT) {
    result->totalObjectCount = SK_MAX_DWG_OBJECT_COUNT + 1;
    sk_set_error(
        result,
        "DWG 对象数量过大（%lu，预算上限 %d），已停止原生解析以避免内存不足。",
        (unsigned long)dwg.num_objects,
        SK_MAX_DWG_OBJECT_COUNT);
    dwg_free(&dwg);
    return 0;
  }

  SKParseContext ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.result = result;
  ctx.dwg = &dwg;
  ctx.capacity = 0;
  ctx.parseOptions = parse_options;
  ctx.hasTextCodepageOverride = codepage_override > 0;
  ctx.textCodepageOverride = codepage_override > 0
                                 ? sk_dwg_codepage_from_external(codepage_override)
                                 : 0;
  result->totalObjectCount = (int)dwg.num_objects;
  result->requestedCodepage = codepage_override;
  result->headerCodepage = (int)dwg.header.codepage;
  result->effectiveCodepage = (int)sk_context_codepage(&ctx);

  const bool parsed = sk_parse_root_entities(&ctx);
  sk_collect_xref_references(&ctx);
  sk_write_unsupported_summary(&ctx);
  sk_write_block_reference_summary(result);
  sk_write_style_table_summary(result, &dwg);
  if (!parsed) {
    if (!result->errorMessage[0]) {
      sk_set_error(result, "DWG 解析中断。");
    }
    if (result->primitives) {
      for (int index = 0; index < result->primitiveCount; index++) {
        sk_free_primitive_members(&result->primitives[index]);
      }
      free(result->primitives);
      result->primitives = NULL;
      result->primitiveCount = 0;
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
                       "未识别到可绘制实体（读取状态 %d）。已支持二维 LINE/ARC/CIRCLE/TEXT/"
                       "MTEXT/LWPOLYLINE/POLYLINE/ELLIPSE/INSERT/MINSERT/DIMENSION/"
                       "HATCH/LEADER/MULTILEADER/SOLID；当前主要未支持：%s。",
                       readStatus, stats);
        } else {
          sk_set_error(result,
                       "未识别到可绘制实体。已支持二维 LINE/ARC/CIRCLE/TEXT/MTEXT/"
                       "LWPOLYLINE/POLYLINE/ELLIPSE/INSERT/MINSERT/DIMENSION/"
                       "HATCH/LEADER/MULTILEADER/SOLID；当前主要未支持：%s。",
                       stats);
        }
      } else {
        if (readStatus != 0) {
          sk_set_error(result,
                       "未识别到可绘制实体（读取状态 %d，当前支持二维 LINE / ARC / CIRCLE / "
                       "TEXT / MTEXT / LWPOLYLINE / POLYLINE / ELLIPSE / INSERT / "
                       "MINSERT / DIMENSION / HATCH / LEADER / MULTILEADER / SOLID / "
                       "常见图层线型）。",
                       readStatus);
        } else {
          sk_set_error(result,
                       "未识别到可绘制实体（当前支持二维 LINE / ARC / CIRCLE / TEXT / "
                       "MTEXT / LWPOLYLINE / POLYLINE / ELLIPSE / INSERT / MINSERT / "
                       "DIMENSION / HATCH / LEADER / MULTILEADER / SOLID / 常见图层线型）。");
        }
      }
    }
    if (result->primitives) {
      for (int index = 0; index < result->primitiveCount; index++) {
        sk_free_primitive_members(&result->primitives[index]);
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
      sk_free_primitive_members(&result->primitives[index]);
    }
    free(result->primitives);
  }
  if (result->xrefs) {
    for (int index = 0; index < result->xrefReferenceCount; index++) {
      sk_free_xref_reference(&result->xrefs[index]);
    }
    free(result->xrefs);
  }

  memset(result, 0, sizeof(*result));
}
