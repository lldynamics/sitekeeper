#include "SiteKeeperLibreDWGShim.h"

#include <dwg_api.h>
#include <ctype.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#ifndef SITEKEEPER_PI
#define SITEKEEPER_PI 3.14159265358979323846264338327950288
#endif

#define SITEKEEPER_MAX_INSERT_DEPTH 8
#define SITEKEEPER_MAX_FILLED_HATCH_POINTS 64

static int sitekeeper_object_matches(const Dwg_Object *object, int type);

typedef struct SiteKeeperLibreDWGTransform {
    double m11;
    double m12;
    double m21;
    double m22;
    double tx;
    double ty;
    int32_t layoutSpace;
} SiteKeeperLibreDWGTransform;

static SiteKeeperLibreDWGTransform sitekeeper_identity_transform(void)
{
    SiteKeeperLibreDWGTransform transform;
    transform.m11 = 1;
    transform.m12 = 0;
    transform.m21 = 0;
    transform.m22 = 1;
    transform.tx = 0;
    transform.ty = 0;
    transform.layoutSpace = 0;
    return transform;
}

static SiteKeeperLibreDWGPoint sitekeeper_transform_point(
    const SiteKeeperLibreDWGTransform *transform,
    SiteKeeperLibreDWGPoint point
)
{
    if (transform == NULL) {
        return point;
    }

    SiteKeeperLibreDWGPoint transformed;
    transformed.x = transform->m11 * point.x + transform->m21 * point.y + transform->tx;
    transformed.y = transform->m12 * point.x + transform->m22 * point.y + transform->ty;
    return transformed;
}

static SiteKeeperLibreDWGTransform sitekeeper_compose_transform(
    SiteKeeperLibreDWGTransform parent,
    SiteKeeperLibreDWGTransform child
)
{
    SiteKeeperLibreDWGTransform result;
    result.m11 = parent.m11 * child.m11 + parent.m21 * child.m12;
    result.m21 = parent.m11 * child.m21 + parent.m21 * child.m22;
    result.tx = parent.m11 * child.tx + parent.m21 * child.ty + parent.tx;
    result.m12 = parent.m12 * child.m11 + parent.m22 * child.m12;
    result.m22 = parent.m12 * child.m21 + parent.m22 * child.m22;
    result.ty = parent.m12 * child.tx + parent.m22 * child.ty + parent.ty;
    result.layoutSpace = parent.layoutSpace;
    return result;
}

static double sitekeeper_transform_rotation(const SiteKeeperLibreDWGTransform *transform)
{
    if (transform == NULL) {
        return 0;
    }
    return atan2(transform->m12, transform->m11);
}

static double sitekeeper_transform_scale(const SiteKeeperLibreDWGTransform *transform)
{
    if (transform == NULL) {
        return 1;
    }
    const double scale = hypot(transform->m11, transform->m12);
    if (!isfinite(scale) || scale <= DBL_EPSILON) {
        return 1;
    }
    return scale;
}

static char *sitekeeper_copy_string(const char *value)
{
    if (value == NULL || value[0] == '\0') {
        value = "0";
    }

    const size_t length = strlen(value);
    char *copy = (char *)malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, value, length + 1);
    return copy;
}

static char *sitekeeper_copy_optional_string(const char *value)
{
    if (value == NULL || value[0] == '\0') {
        return NULL;
    }
    const size_t length = strlen(value);
    char *copy = (char *)malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, value, length + 1);
    return copy;
}

static void sitekeeper_reset_result(SiteKeeperLibreDWGEntityResult *result)
{
    memset(result, 0, sizeof(*result));
    result->trace.minX = DBL_MAX;
    result->trace.minY = DBL_MAX;
    result->trace.maxX = -DBL_MAX;
    result->trace.maxY = -DBL_MAX;
}

static void sitekeeper_include_point(SiteKeeperLibreDWGTrace *trace, double x, double y)
{
    if (!isfinite(x) || !isfinite(y)) {
        return;
    }
    if (x < trace->minX) {
        trace->minX = x;
    }
    if (y < trace->minY) {
        trace->minY = y;
    }
    if (x > trace->maxX) {
        trace->maxX = x;
    }
    if (y > trace->maxY) {
        trace->maxY = y;
    }
}

static uint32_t sitekeeper_aci_argb(int32_t index)
{
    switch (index) {
    case 1:
        return 0xFFFF0000;
    case 2:
        return 0xFFFFFF00;
    case 3:
        return 0xFF00FF00;
    case 4:
        return 0xFF00FFFF;
    case 5:
        return 0xFF0000FF;
    case 6:
        return 0xFFFF00FF;
    case 7:
        return 0xFF2F3437;
    case 8:
        return 0xFF808080;
    case 9:
        return 0xFFC0C0C0;
    default: {
        const double normalized = (double)((index - 1) % 24) / 24.0;
        const double hue = normalized * 6.0;
        const double c = 1.0;
        const double x = c * (1.0 - fabs(fmod(hue, 2.0) - 1.0));
        double r = 0;
        double g = 0;
        double b = 0;
        if (hue < 1.0) {
            r = c;
            g = x;
        } else if (hue < 2.0) {
            r = x;
            g = c;
        } else if (hue < 3.0) {
            g = c;
            b = x;
        } else if (hue < 4.0) {
            g = x;
            b = c;
        } else if (hue < 5.0) {
            r = x;
            b = c;
        } else {
            r = c;
            b = x;
        }
        return 0xFF000000
            | ((uint32_t)lrint(r * 255.0) << 16)
            | ((uint32_t)lrint(g * 255.0) << 8)
            | (uint32_t)lrint(b * 255.0);
    }
    }
}

static uint32_t sitekeeper_color_argb(const Dwg_Color *color, uint32_t unresolved_color)
{
    if (color == NULL) {
        return unresolved_color;
    }

    if (color->method == DWG_COLOR_METHOD_TRUECOLOR) {
        const uint32_t rgb = (uint32_t)(color->rgb & 0x00FFFFFF);
        if (rgb != 0 && rgb != 0x00000100 && rgb != 0x00000101) {
            return 0xFF000000 | rgb;
        }
    }

    const int32_t aci = color->index < 0 ? -color->index : color->index;
    if (aci > 0 && aci < 256) {
        return sitekeeper_aci_argb(aci);
    }

    if (color->method == DWG_COLOR_METHOD_ACI && aci > 0 && aci < 256) {
        return sitekeeper_aci_argb(aci);
    }

    const uint32_t rgb = (uint32_t)(color->rgb & 0x00FFFFFF);
    if (rgb != 0 && rgb != 0x00000100 && rgb != 0x00000101) {
        return 0xFF000000 | rgb;
    }

    return unresolved_color;
}

static uint32_t sitekeeper_entity_color_argb(Dwg_Object_Entity *entity)
{
    if (entity == NULL) {
        return 0xFF0A84FF;
    }

    const uint32_t entity_color = sitekeeper_color_argb(&entity->color, 0);
    if (entity_color != 0) {
        return entity_color;
    }

    Dwg_Object_LAYER *layer = dwg_get_entity_layer(entity);
    if (layer != NULL) {
        const uint32_t layer_color = sitekeeper_color_argb(&layer->color, 0);
        if (layer_color != 0) {
            return layer_color;
        }
    }

    return 0xFF0A84FF;
}

static char *sitekeeper_layer_name(Dwg_Object_Entity *entity)
{
    Dwg_Object_LAYER *layer = dwg_get_entity_layer(entity);
    if (layer != NULL && layer->name != NULL && layer->name[0] != '\0') {
        return sitekeeper_copy_string(layer->name);
    }
    return sitekeeper_copy_string("0");
}

static Dwg_Object_STYLE *sitekeeper_style_from_ref(Dwg_Data *dwg, Dwg_Object_Ref *style_ref)
{
    if (style_ref == NULL) {
        return NULL;
    }

    Dwg_Object *style_object = style_ref->obj;
    if (style_object == NULL && dwg != NULL) {
        style_object = dwg_ref_object_silent(dwg, style_ref);
    }
    if (style_object == NULL || style_object->tio.object == NULL
        || style_object->tio.object->tio.STYLE == NULL) {
        return NULL;
    }
    if (!sitekeeper_object_matches(style_object, (int)DWG_TYPE_STYLE)) {
        return NULL;
    }
    return style_object->tio.object->tio.STYLE;
}

static Dwg_Object_DIMSTYLE *sitekeeper_dimstyle_from_ref(Dwg_Data *dwg, Dwg_Object_Ref *dimstyle_ref)
{
    if (dimstyle_ref == NULL) {
        return NULL;
    }

    Dwg_Object *dimstyle_object = dimstyle_ref->obj;
    if (dimstyle_object == NULL && dwg != NULL) {
        dimstyle_object = dwg_ref_object_silent(dwg, dimstyle_ref);
    }
    if (dimstyle_object == NULL || dimstyle_object->tio.object == NULL
        || dimstyle_object->tio.object->tio.DIMSTYLE == NULL) {
        return NULL;
    }
    if (!sitekeeper_object_matches(dimstyle_object, (int)DWG_TYPE_DIMSTYLE)) {
        return NULL;
    }
    return dimstyle_object->tio.object->tio.DIMSTYLE;
}

static double sitekeeper_dimstyle_text_height(Dwg_Object_DIMSTYLE *dimstyle)
{
    if (dimstyle == NULL || !isfinite(dimstyle->DIMTXT) || dimstyle->DIMTXT <= 0) {
        return 2.5;
    }
    const double scale = isfinite(dimstyle->DIMSCALE) && dimstyle->DIMSCALE > DBL_EPSILON
        ? dimstyle->DIMSCALE
        : 1.0;
    return dimstyle->DIMTXT * scale;
}

static const char *sitekeeper_style_name(Dwg_Object_STYLE *style)
{
    if (style != NULL && style->name != NULL && style->name[0] != '\0') {
        return style->name;
    }
    return "Standard";
}

static const char *sitekeeper_style_font_file(Dwg_Object_STYLE *style)
{
    if (style != NULL && style->font_file != NULL && style->font_file[0] != '\0') {
        return style->font_file;
    }
    return NULL;
}

static const char *sitekeeper_style_bigfont_file(Dwg_Object_STYLE *style)
{
    if (style != NULL && style->bigfont_file != NULL && style->bigfont_file[0] != '\0') {
        return style->bigfont_file;
    }
    return NULL;
}

static char *sitekeeper_handle_string(const Dwg_Object *object)
{
    char buffer[32];
    if (object == NULL) {
        return sitekeeper_copy_string("");
    }
    snprintf(buffer, sizeof(buffer), "%llX", (unsigned long long)object->handle.value);
    return sitekeeper_copy_string(buffer);
}

static char *sitekeeper_handle_string_with_suffix(const Dwg_Object *object, unsigned long suffix)
{
    char buffer[48];
    if (object == NULL) {
        snprintf(buffer, sizeof(buffer), "0-%lu", suffix);
    } else {
        snprintf(buffer, sizeof(buffer), "%llX-%lu", (unsigned long long)object->handle.value, suffix);
    }
    return sitekeeper_copy_string(buffer);
}

static Dwg_Object *sitekeeper_object_for_entity(Dwg_Object_Entity *entity)
{
    if (entity == NULL || entity->dwg == NULL || entity->objid >= entity->dwg->num_objects) {
        return NULL;
    }
    return &entity->dwg->object[entity->objid];
}

static int sitekeeper_object_matches(const Dwg_Object *object, int type)
{
    if (object == NULL) {
        return 0;
    }
    return (int)object->type == type || (int)object->fixedtype == type;
}

static const char *sitekeeper_safe_string(const char *value)
{
    return value != NULL ? value : "";
}

static int sitekeeper_contains_case_insensitive(const char *haystack, const char *needle)
{
    if (haystack == NULL || needle == NULL || needle[0] == '\0') {
        return 0;
    }

    const size_t needle_length = strlen(needle);
    for (const char *cursor = haystack; *cursor != '\0'; cursor++) {
        size_t offset = 0;
        while (offset < needle_length
            && cursor[offset] != '\0'
            && toupper((unsigned char)cursor[offset]) == toupper((unsigned char)needle[offset])) {
            offset += 1;
        }
        if (offset == needle_length) {
            return 1;
        }
    }
    return 0;
}

static int sitekeeper_object_field_contains(const Dwg_Object *object, const char *token)
{
    if (object == NULL || token == NULL) {
        return 0;
    }
    if (sitekeeper_contains_case_insensitive(object->name, token)
        || sitekeeper_contains_case_insensitive(object->dxfname, token)) {
        return 1;
    }
    if (object->klass != NULL) {
        return sitekeeper_contains_case_insensitive(object->klass->appname, token)
            || sitekeeper_contains_case_insensitive(object->klass->cppname, token)
            || sitekeeper_contains_case_insensitive(object->klass->dxfname, token);
    }
    return 0;
}

static int sitekeeper_object_is_tianzheng(const Dwg_Object *object)
{
    return sitekeeper_object_field_contains(object, "TCH_")
        || sitekeeper_object_field_contains(object, "TCH")
        || sitekeeper_object_field_contains(object, "TIANZHENG")
        || sitekeeper_object_field_contains(object, "TARCH");
}

static int sitekeeper_is_text_candidate_code_unit(uint16_t value)
{
    return value == 0x0009
        || value == 0x000A
        || value == 0x000D
        || (value >= 0x0020 && value <= 0xD7FF)
        || (value >= 0xE000 && value <= 0xFFFD);
}

static int sitekeeper_is_cjk_code_unit(uint16_t value)
{
    return (value >= 0x3400 && value <= 0x4DBF)
        || (value >= 0x4E00 && value <= 0x9FFF)
        || (value >= 0xF900 && value <= 0xFAFF);
}

static size_t sitekeeper_utf8_code_unit_length(uint16_t value)
{
    if (value < 0x80) {
        return 1;
    }
    if (value < 0x800) {
        return 2;
    }
    return 3;
}

static char *sitekeeper_copy_utf16le_candidate(const BITCODE_RC *bytes, BITCODE_BL byte_count)
{
    if (bytes == NULL || byte_count < 4) {
        return NULL;
    }

    size_t best_start = 0;
    size_t best_units = 0;
    size_t best_cjk = 0;
    const size_t count = (size_t)byte_count;

    for (size_t offset = 0; offset < 2 && offset + 1 < count; offset++) {
        size_t index = offset;
        while (index + 1 < count) {
            size_t run_start = index;
            size_t run_units = 0;
            size_t run_cjk = 0;
            while (index + 1 < count) {
                const uint16_t value = (uint16_t)bytes[index] | ((uint16_t)bytes[index + 1] << 8);
                if (value == 0 || !sitekeeper_is_text_candidate_code_unit(value)) {
                    break;
                }
                run_units += 1;
                if (sitekeeper_is_cjk_code_unit(value)) {
                    run_cjk += 1;
                }
                index += 2;
                if (run_units >= 160) {
                    break;
                }
            }
            if (run_cjk > 0 && run_units >= 2 && run_units > best_units) {
                best_start = run_start;
                best_units = run_units;
                best_cjk = run_cjk;
            }
            index += 2;
        }
    }

    if (best_units == 0 || best_cjk == 0) {
        return NULL;
    }

    size_t output_capacity = 1;
    for (size_t unit = 0; unit < best_units; unit++) {
        const size_t byte_index = best_start + unit * 2;
        const uint16_t value = (uint16_t)bytes[byte_index] | ((uint16_t)bytes[byte_index + 1] << 8);
        output_capacity += sitekeeper_utf8_code_unit_length(value);
    }

    char *output = (char *)malloc(output_capacity);
    if (output == NULL) {
        return NULL;
    }

    size_t out = 0;
    for (size_t unit = 0; unit < best_units; unit++) {
        const size_t byte_index = best_start + unit * 2;
        const uint16_t value = (uint16_t)bytes[byte_index] | ((uint16_t)bytes[byte_index + 1] << 8);
        if (value < 0x80) {
            output[out++] = (char)value;
        } else if (value < 0x800) {
            output[out++] = (char)(0xC0 | (value >> 6));
            output[out++] = (char)(0x80 | (value & 0x3F));
        } else {
            output[out++] = (char)(0xE0 | (value >> 12));
            output[out++] = (char)(0x80 | ((value >> 6) & 0x3F));
            output[out++] = (char)(0x80 | (value & 0x3F));
        }
    }
    output[out] = '\0';
    return output;
}

static int sitekeeper_is_ascii_text_byte(unsigned char value)
{
    return value == '\t'
        || value == '\n'
        || value == '\r'
        || (value >= 0x20 && value <= 0x7E);
}

static char *sitekeeper_copy_ascii_candidate(const BITCODE_RC *bytes, BITCODE_BL byte_count)
{
    if (bytes == NULL || byte_count < 4) {
        return NULL;
    }

    size_t best_start = 0;
    size_t best_length = 0;
    size_t best_alpha = 0;
    const size_t count = (size_t)byte_count;

    size_t index = 0;
    while (index < count) {
        while (index < count && !sitekeeper_is_ascii_text_byte((unsigned char)bytes[index])) {
            index += 1;
        }
        const size_t run_start = index;
        size_t run_length = 0;
        size_t run_alpha = 0;
        while (index < count && sitekeeper_is_ascii_text_byte((unsigned char)bytes[index])) {
            if (isalpha((unsigned char)bytes[index])) {
                run_alpha += 1;
            }
            run_length += 1;
            index += 1;
            if (run_length >= 180) {
                break;
            }
        }
        if (run_length >= 4 && run_alpha > 0 && run_length > best_length) {
            best_start = run_start;
            best_length = run_length;
            best_alpha = run_alpha;
        }
    }

    if (best_length == 0 || best_alpha == 0) {
        return NULL;
    }

    char *output = (char *)malloc(best_length + 1);
    if (output == NULL) {
        return NULL;
    }
    memcpy(output, bytes + best_start, best_length);
    output[best_length] = '\0';
    return output;
}

static char *sitekeeper_proxy_text_candidate(const Dwg_Object *object)
{
    if (object == NULL
        || !sitekeeper_object_matches(object, (int)DWG_TYPE_PROXY_ENTITY)
        || object->tio.entity == NULL
        || object->tio.entity->tio.PROXY_ENTITY == NULL) {
        return NULL;
    }

    Dwg_Entity_PROXY_ENTITY *proxy = object->tio.entity->tio.PROXY_ENTITY;
    char *candidate = sitekeeper_copy_utf16le_candidate(proxy->data, proxy->data_size);
    if (candidate != NULL) {
        return candidate;
    }
    candidate = sitekeeper_copy_utf16le_candidate(proxy->proxy_data, proxy->proxy_data_size);
    if (candidate != NULL) {
        return candidate;
    }
    candidate = sitekeeper_copy_ascii_candidate(proxy->data, proxy->data_size);
    if (candidate != NULL) {
        return candidate;
    }
    return sitekeeper_copy_ascii_candidate(proxy->proxy_data, proxy->proxy_data_size);
}

static char *sitekeeper_object_display_name(const Dwg_Object *object)
{
    if (object == NULL) {
        return sitekeeper_copy_string("UNKNOWN");
    }
    if (object->dxfname != NULL && object->dxfname[0] != '\0') {
        return sitekeeper_copy_string(object->dxfname);
    }
    if (object->name != NULL && object->name[0] != '\0') {
        return sitekeeper_copy_string(object->name);
    }
    if (object->klass != NULL && object->klass->dxfname != NULL && object->klass->dxfname[0] != '\0') {
        return sitekeeper_copy_string(object->klass->dxfname);
    }
    if (object->klass != NULL && object->klass->cppname != NULL && object->klass->cppname[0] != '\0') {
        return sitekeeper_copy_string(object->klass->cppname);
    }

    char buffer[64];
    snprintf(
        buffer,
        sizeof(buffer),
        "type=%d,fixedtype=%d",
        (int)object->type,
        (int)object->fixedtype
    );
    return sitekeeper_copy_string(buffer);
}

static char *sitekeeper_proxy_reason(const Dwg_Object *object, int is_tianzheng)
{
    long class_id = -1;
    long proxy_data_size = -1;
    long entity_data_size = -1;
    char *text_candidate = NULL;
    if (object != NULL
        && sitekeeper_object_matches(object, (int)DWG_TYPE_PROXY_ENTITY)
        && object->tio.entity != NULL
        && object->tio.entity->tio.PROXY_ENTITY != NULL) {
        Dwg_Entity_PROXY_ENTITY *proxy = object->tio.entity->tio.PROXY_ENTITY;
        class_id = (long)proxy->class_id;
        proxy_data_size = (long)proxy->proxy_data_size;
        entity_data_size = (long)proxy->data_size;
        text_candidate = sitekeeper_proxy_text_candidate(object);
    }

    char buffer[768];
    snprintf(
        buffer,
        sizeof(buffer),
        "%s; name=%s; dxfname=%s; app=%s; cpp=%s; class=%s; type=%d; fixedtype=%d; classId=%ld; proxyDataBytes=%ld; entityDataBytes=%ld%s%.180s",
        is_tianzheng
            ? "Tianzheng/TCH proxy object preserved as diagnostic metadata; custom object geometry is not decoded by the CAD Metal PoC."
            : "DWG proxy entity preserved as diagnostic metadata; proxy graphics are not decoded by the CAD Metal PoC.",
        sitekeeper_safe_string(object != NULL ? object->name : NULL),
        sitekeeper_safe_string(object != NULL ? object->dxfname : NULL),
        sitekeeper_safe_string(object != NULL && object->klass != NULL ? object->klass->appname : NULL),
        sitekeeper_safe_string(object != NULL && object->klass != NULL ? object->klass->cppname : NULL),
        sitekeeper_safe_string(object != NULL && object->klass != NULL ? object->klass->dxfname : NULL),
        object != NULL ? (int)object->type : -1,
        object != NULL ? (int)object->fixedtype : -1,
        class_id,
        proxy_data_size,
        entity_data_size,
        text_candidate != NULL ? "; textCandidate=" : "",
        text_candidate != NULL ? text_candidate : ""
    );
    free(text_candidate);
    return sitekeeper_copy_string(buffer);
}

static int sitekeeper_entity_is_visible(const Dwg_Object_Entity *entity)
{
    return entity != NULL && entity->invisible == 0;
}

static int32_t sitekeeper_entity_layout_space(const Dwg_Object_Entity *entity)
{
    if (entity == NULL) {
        return 0;
    }
    return entity->entmode == 1 ? 1 : 0;
}

static double sitekeeper_line_weight(const Dwg_Object_Entity *entity)
{
    if (entity == NULL || entity->linewt <= 0) {
        return 2.0;
    }
    return (double)entity->linewt / 100.0;
}

static SiteKeeperLibreDWGPoint *sitekeeper_copy_points(
    const SiteKeeperLibreDWGPoint *points,
    int32_t point_count,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (points == NULL || point_count <= 0) {
        return NULL;
    }

    SiteKeeperLibreDWGPoint *copy = (SiteKeeperLibreDWGPoint *)calloc(
        (size_t)point_count,
        sizeof(SiteKeeperLibreDWGPoint)
    );
    if (copy == NULL) {
        return NULL;
    }
    for (int32_t index = 0; index < point_count; index++) {
        copy[index] = sitekeeper_transform_point(transform, points[index]);
    }
    return copy;
}

static int sitekeeper_ensure_entity_capacity(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_capacity,
    int32_t required_count
)
{
    if (result == NULL || entity_capacity == NULL || required_count <= *entity_capacity) {
        return 1;
    }

    int32_t next_capacity = *entity_capacity > 0 ? *entity_capacity : 32;
    while (next_capacity < required_count) {
        if (next_capacity > INT32_MAX / 2) {
            return 0;
        }
        next_capacity *= 2;
    }

    SiteKeeperLibreDWGEntity *next_entities = (SiteKeeperLibreDWGEntity *)realloc(
        result->entities,
        sizeof(SiteKeeperLibreDWGEntity) * (size_t)next_capacity
    );
    if (next_entities == NULL) {
        return 0;
    }

    memset(
        next_entities + *entity_capacity,
        0,
        sizeof(SiteKeeperLibreDWGEntity) * (size_t)(next_capacity - *entity_capacity)
    );
    result->entities = next_entities;
    *entity_capacity = next_capacity;
    return 1;
}

static int sitekeeper_append_entity(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    int32_t kind,
    const SiteKeeperLibreDWGPoint *points,
    int32_t point_count,
    int32_t is_closed,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (result == NULL || result->entities == NULL || entity_count == NULL || point_count < 2) {
        return 0;
    }
    if (!sitekeeper_ensure_entity_capacity(result, entity_capacity, *entity_count + 1)) {
        return 0;
    }

    SiteKeeperLibreDWGPoint *points_copy = sitekeeper_copy_points(points, point_count, transform);
    if (points_copy == NULL) {
        return 0;
    }

    SiteKeeperLibreDWGEntity *out = &result->entities[*entity_count];
    out->kind = kind;
    out->points = points_copy;
    out->pointCount = point_count;
    out->isClosed = is_closed;
    out->layoutSpace = transform != NULL ? transform->layoutSpace : sitekeeper_entity_layout_space(entity);
    out->layerName = sitekeeper_layer_name(entity);
    out->sourceHandle = sitekeeper_handle_string(object);
    out->colorARGB = sitekeeper_entity_color_argb(entity);
    out->lineWeight = sitekeeper_line_weight(entity);

    for (int32_t index = 0; index < point_count; index++) {
        sitekeeper_include_point(&result->trace, points_copy[index].x, points_copy[index].y);
    }

    *entity_count += 1;
    return 1;
}

static int sitekeeper_append_text_entity(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    int32_t kind,
    const char *raw_text,
    double insertion_x,
    double insertion_y,
    double height,
    double rotation,
    double width_factor,
    double box_width,
    double box_height,
    int32_t horizontal_alignment,
    int32_t vertical_alignment,
    Dwg_Object_STYLE *style,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (result == NULL || entity_count == NULL || raw_text == NULL || raw_text[0] == '\0') {
        return 0;
    }
    if (!sitekeeper_ensure_entity_capacity(result, entity_capacity, *entity_count + 1)) {
        return 0;
    }

    char *text_copy = sitekeeper_copy_optional_string(raw_text);
    if (text_copy == NULL) {
        return 0;
    }

    SiteKeeperLibreDWGPoint insertion = { insertion_x, insertion_y };
    insertion = sitekeeper_transform_point(transform, insertion);

    SiteKeeperLibreDWGEntity *out = &result->entities[*entity_count];
    out->kind = kind;
    out->points = NULL;
    out->pointCount = 0;
    out->isClosed = 0;
    out->layoutSpace = transform != NULL ? transform->layoutSpace : sitekeeper_entity_layout_space(entity);
    out->layerName = sitekeeper_layer_name(entity);
    out->sourceHandle = sitekeeper_handle_string(object);
    out->rawText = text_copy;
    out->textStyleName = sitekeeper_copy_string(sitekeeper_style_name(style));
    out->fontName = sitekeeper_copy_optional_string(sitekeeper_style_font_file(style));
    out->bigFontName = sitekeeper_copy_optional_string(sitekeeper_style_bigfont_file(style));
    out->colorARGB = sitekeeper_entity_color_argb(entity);
    out->lineWeight = sitekeeper_line_weight(entity);
    out->textX = insertion.x;
    out->textY = insertion.y;
    out->textHeight = (isfinite(height) && height > 0 ? height : 2.5) * sitekeeper_transform_scale(transform);
    out->textRotation = (isfinite(rotation) ? rotation : 0) + sitekeeper_transform_rotation(transform);
    out->textWidthFactor = isfinite(width_factor) && width_factor > DBL_EPSILON ? width_factor : 1.0;
    out->textBoxWidth = isfinite(box_width) && box_width > 0 ? box_width * sitekeeper_transform_scale(transform) : 0;
    out->textBoxHeight = isfinite(box_height) && box_height > 0 ? box_height * sitekeeper_transform_scale(transform) : 0;
    out->textHorizontalAlignment = horizontal_alignment;
    out->textVerticalAlignment = vertical_alignment;

    sitekeeper_include_point(&result->trace, insertion.x, insertion.y);
    *entity_count += 1;
    result->trace.exportedTextCount += 1;
    return 1;
}

static int sitekeeper_append_proxy_entity(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    int32_t kind,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (result == NULL || entity_count == NULL) {
        return 0;
    }
    if (!sitekeeper_ensure_entity_capacity(result, entity_capacity, *entity_count + 1)) {
        return 0;
    }

    const int is_tianzheng = kind == SiteKeeperLibreDWGEntityKindTianzhengProxy;
    SiteKeeperLibreDWGEntity *out = &result->entities[*entity_count];
    out->kind = kind;
    out->points = NULL;
    out->pointCount = 0;
    out->isClosed = 0;
    out->layoutSpace = transform != NULL ? transform->layoutSpace : sitekeeper_entity_layout_space(entity);
    out->layerName = sitekeeper_layer_name(entity);
    out->sourceHandle = sitekeeper_handle_string(object);
    out->objectName = sitekeeper_object_display_name(object);
    out->unsupportedReason = sitekeeper_proxy_reason(object, is_tianzheng);
    out->colorARGB = sitekeeper_entity_color_argb(entity);
    out->lineWeight = sitekeeper_line_weight(entity);

    *entity_count += 1;
    result->trace.exportedProxyEntityCount += 1;
    if (is_tianzheng) {
        result->trace.exportedTianzhengProxyCount += 1;
    }
    return 1;
}

static void sitekeeper_format_measurement(double measurement, char *buffer, size_t buffer_size)
{
    if (buffer == NULL || buffer_size == 0) {
        return;
    }
    if (!isfinite(measurement)) {
        snprintf(buffer, buffer_size, "0");
        return;
    }

    const double rounded = round(measurement * 1000.0) / 1000.0;
    if (fabs(rounded - round(rounded)) < 0.0001) {
        snprintf(buffer, buffer_size, "%.0f", rounded);
        return;
    }
    snprintf(buffer, buffer_size, "%.3f", rounded);
    size_t length = strlen(buffer);
    while (length > 0 && buffer[length - 1] == '0') {
        buffer[length - 1] = '\0';
        length -= 1;
    }
    if (length > 0 && buffer[length - 1] == '.') {
        buffer[length - 1] = '\0';
    }
}

static const char *sitekeeper_dimension_text(
    const char *user_text,
    double measurement,
    char *buffer,
    size_t buffer_size
)
{
    if (buffer == NULL || buffer_size == 0) {
        return user_text;
    }

    char measurement_buffer[64];
    sitekeeper_format_measurement(measurement, measurement_buffer, sizeof(measurement_buffer));

    if (user_text == NULL || user_text[0] == '\0' || strcmp(user_text, "<>") == 0) {
        snprintf(buffer, buffer_size, "%s", measurement_buffer);
        return buffer;
    }

    const char *placeholder = strstr(user_text, "<>");
    if (placeholder == NULL) {
        return user_text;
    }

    const size_t prefix_length = (size_t)(placeholder - user_text);
    snprintf(
        buffer,
        buffer_size,
        "%.*s%s%s",
        (int)prefix_length,
        user_text,
        measurement_buffer,
        placeholder + 2
    );
    return buffer;
}

static int sitekeeper_point_is_finite(SiteKeeperLibreDWGPoint point)
{
    return isfinite(point.x) && isfinite(point.y);
}

static double sitekeeper_point_distance(SiteKeeperLibreDWGPoint start, SiteKeeperLibreDWGPoint end)
{
    return hypot(end.x - start.x, end.y - start.y);
}

static SiteKeeperLibreDWGPoint sitekeeper_midpoint(
    SiteKeeperLibreDWGPoint start,
    SiteKeeperLibreDWGPoint end
)
{
    SiteKeeperLibreDWGPoint point;
    point.x = (start.x + end.x) / 2.0;
    point.y = (start.y + end.y) / 2.0;
    return point;
}

static SiteKeeperLibreDWGPoint sitekeeper_project_point_to_axis(
    SiteKeeperLibreDWGPoint point,
    SiteKeeperLibreDWGPoint line_point,
    double axis_x,
    double axis_y
)
{
    const double dx = point.x - line_point.x;
    const double dy = point.y - line_point.y;
    const double distance_along_axis = dx * axis_x + dy * axis_y;
    SiteKeeperLibreDWGPoint projected;
    projected.x = line_point.x + axis_x * distance_along_axis;
    projected.y = line_point.y + axis_y * distance_along_axis;
    return projected;
}

static int32_t sitekeeper_make_dimension_display_points(
    SiteKeeperLibreDWGPoint start,
    SiteKeeperLibreDWGPoint end,
    SiteKeeperLibreDWGPoint dimension_line_point,
    int has_dimension_line_point,
    SiteKeeperLibreDWGPoint text_point,
    int has_text_point,
    double axis_rotation,
    int has_axis_rotation,
    SiteKeeperLibreDWGPoint *points,
    int32_t capacity
)
{
    if (points == NULL || capacity < 4 || !sitekeeper_point_is_finite(start)
        || !sitekeeper_point_is_finite(end)) {
        return 0;
    }

    const double measured_length = sitekeeper_point_distance(start, end);
    if (!isfinite(measured_length) || measured_length <= DBL_EPSILON) {
        points[0] = start;
        points[1] = end;
        return 2;
    }

    double axis_x;
    double axis_y;
    if (has_axis_rotation && isfinite(axis_rotation)) {
        axis_x = cos(axis_rotation);
        axis_y = sin(axis_rotation);
    } else {
        axis_x = (end.x - start.x) / measured_length;
        axis_y = (end.y - start.y) / measured_length;
    }

    SiteKeeperLibreDWGPoint reference = sitekeeper_midpoint(start, end);
    if (has_dimension_line_point && sitekeeper_point_is_finite(dimension_line_point)) {
        reference = dimension_line_point;
    } else if (has_text_point && sitekeeper_point_is_finite(text_point)) {
        reference = text_point;
    }

    SiteKeeperLibreDWGPoint dimension_start = sitekeeper_project_point_to_axis(
        start,
        reference,
        axis_x,
        axis_y
    );
    SiteKeeperLibreDWGPoint dimension_end = sitekeeper_project_point_to_axis(
        end,
        reference,
        axis_x,
        axis_y
    );
    if (sitekeeper_point_distance(dimension_start, dimension_end) <= DBL_EPSILON) {
        points[0] = start;
        points[1] = end;
        return 2;
    }

    points[0] = start;
    points[1] = dimension_start;
    points[2] = dimension_end;
    points[3] = end;
    return 4;
}

static int sitekeeper_attach_text_to_entity(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t entity_index,
    const char *raw_text,
    double insertion_x,
    double insertion_y,
    double height,
    double rotation,
    double width_factor,
    int32_t horizontal_alignment,
    int32_t vertical_alignment,
    Dwg_Object_STYLE *style,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (result == NULL || result->entities == NULL || entity_index < 0
        || raw_text == NULL || raw_text[0] == '\0') {
        return 0;
    }

    SiteKeeperLibreDWGEntity *out = &result->entities[entity_index];
    out->rawText = sitekeeper_copy_optional_string(raw_text);
    if (out->rawText == NULL) {
        return 0;
    }
    out->textStyleName = sitekeeper_copy_string(sitekeeper_style_name(style));
    out->fontName = sitekeeper_copy_optional_string(sitekeeper_style_font_file(style));
    out->bigFontName = sitekeeper_copy_optional_string(sitekeeper_style_bigfont_file(style));

    SiteKeeperLibreDWGPoint insertion = { insertion_x, insertion_y };
    insertion = sitekeeper_transform_point(transform, insertion);
    out->textX = insertion.x;
    out->textY = insertion.y;
    out->textHeight = (isfinite(height) && height > 0 ? height : 2.5) * sitekeeper_transform_scale(transform);
    out->textRotation = (isfinite(rotation) ? rotation : 0) + sitekeeper_transform_rotation(transform);
    out->textWidthFactor = isfinite(width_factor) && width_factor > DBL_EPSILON ? width_factor : 1.0;
    out->textHorizontalAlignment = horizontal_alignment;
    out->textVerticalAlignment = vertical_alignment;
    sitekeeper_include_point(&result->trace, insertion.x, insertion.y);
    return 1;
}

static int32_t sitekeeper_circle_segment_count(double radius)
{
    if (!isfinite(radius) || radius <= 0) {
        return 0;
    }
    return 72;
}

static int32_t sitekeeper_arc_segment_count(double start_angle, double end_angle)
{
    double span = end_angle - start_angle;
    while (span <= 0) {
        span += SITEKEEPER_PI * 2.0;
    }
    const double step = SITEKEEPER_PI / 24.0;
    int32_t count = (int32_t)ceil(span / step);
    if (count < 8) {
        count = 8;
    }
    if (count > 96) {
        count = 96;
    }
    return count;
}

static SiteKeeperLibreDWGPoint *sitekeeper_make_circle_points(
    double center_x,
    double center_y,
    double radius,
    int32_t *point_count
)
{
    *point_count = sitekeeper_circle_segment_count(radius);
    if (*point_count <= 0) {
        return NULL;
    }

    SiteKeeperLibreDWGPoint *points = (SiteKeeperLibreDWGPoint *)calloc(
        (size_t)*point_count,
        sizeof(SiteKeeperLibreDWGPoint)
    );
    if (points == NULL) {
        *point_count = 0;
        return NULL;
    }

    for (int32_t index = 0; index < *point_count; index++) {
        double angle = SITEKEEPER_PI * 2.0 * (double)index / (double)*point_count;
        points[index].x = center_x + cos(angle) * radius;
        points[index].y = center_y + sin(angle) * radius;
    }
    return points;
}

static SiteKeeperLibreDWGPoint *sitekeeper_make_arc_points(
    double center_x,
    double center_y,
    double radius,
    double start_angle,
    double end_angle,
    int32_t *point_count
)
{
    int32_t segments = sitekeeper_arc_segment_count(start_angle, end_angle);
    *point_count = segments + 1;
    if (!isfinite(radius) || radius <= 0 || segments <= 0) {
        *point_count = 0;
        return NULL;
    }

    double span = end_angle - start_angle;
    while (span <= 0) {
        span += SITEKEEPER_PI * 2.0;
    }

    SiteKeeperLibreDWGPoint *points = (SiteKeeperLibreDWGPoint *)calloc(
        (size_t)*point_count,
        sizeof(SiteKeeperLibreDWGPoint)
    );
    if (points == NULL) {
        *point_count = 0;
        return NULL;
    }

    for (int32_t index = 0; index < *point_count; index++) {
        double t = (double)index / (double)segments;
        double angle = start_angle + span * t;
        points[index].x = center_x + cos(angle) * radius;
        points[index].y = center_y + sin(angle) * radius;
    }
    return points;
}

static int sitekeeper_push_polyline_point(
    SiteKeeperLibreDWGPoint **points,
    int32_t *point_count,
    int32_t *point_capacity,
    SiteKeeperLibreDWGPoint point
)
{
    if (points == NULL || point_count == NULL || point_capacity == NULL) {
        return 0;
    }
    if (!isfinite(point.x) || !isfinite(point.y)) {
        return 1;
    }
    if (*point_count > 0) {
        SiteKeeperLibreDWGPoint previous = (*points)[*point_count - 1];
        if (fabs(previous.x - point.x) < 0.000001 && fabs(previous.y - point.y) < 0.000001) {
            return 1;
        }
    }
    if (*point_count >= *point_capacity) {
        int32_t next_capacity = *point_capacity > 0 ? *point_capacity * 2 : 16;
        SiteKeeperLibreDWGPoint *next_points = (SiteKeeperLibreDWGPoint *)realloc(
            *points,
            sizeof(SiteKeeperLibreDWGPoint) * (size_t)next_capacity
        );
        if (next_points == NULL) {
            return 0;
        }
        *points = next_points;
        *point_capacity = next_capacity;
    }
    (*points)[*point_count] = point;
    *point_count += 1;
    return 1;
}

static int sitekeeper_append_bulge_segment_points(
    SiteKeeperLibreDWGPoint **points,
    int32_t *point_count,
    int32_t *point_capacity,
    SiteKeeperLibreDWGPoint start,
    SiteKeeperLibreDWGPoint end,
    double bulge
)
{
    if (fabs(bulge) < 0.000001) {
        return sitekeeper_push_polyline_point(points, point_count, point_capacity, end);
    }

    const double dx = end.x - start.x;
    const double dy = end.y - start.y;
    const double chord = hypot(dx, dy);
    if (!isfinite(chord) || chord <= DBL_EPSILON) {
        return 1;
    }

    const double theta = 4.0 * atan(bulge);
    const double radius = chord * (1.0 + bulge * bulge) / (4.0 * fabs(bulge));
    const double center_offset = chord * (1.0 - bulge * bulge) / (4.0 * bulge);
    const double mid_x = (start.x + end.x) / 2.0;
    const double mid_y = (start.y + end.y) / 2.0;
    const double normal_x = -dy / chord;
    const double normal_y = dx / chord;
    const double center_x = mid_x + normal_x * center_offset;
    const double center_y = mid_y + normal_y * center_offset;
    if (!isfinite(radius) || radius <= DBL_EPSILON || !isfinite(center_x) || !isfinite(center_y)) {
        return sitekeeper_push_polyline_point(points, point_count, point_capacity, end);
    }

    const double start_angle = atan2(start.y - center_y, start.x - center_x);
    double end_angle = atan2(end.y - center_y, end.x - center_x);
    double sweep = end_angle - start_angle;
    if (theta > 0) {
        while (sweep <= 0) {
            sweep += SITEKEEPER_PI * 2.0;
        }
    } else {
        while (sweep >= 0) {
            sweep -= SITEKEEPER_PI * 2.0;
        }
    }

    int32_t segments = (int32_t)ceil(fabs(sweep) / (SITEKEEPER_PI / 24.0));
    if (segments < 4) {
        segments = 4;
    }
    if (segments > 96) {
        segments = 96;
    }

    for (int32_t index = 1; index <= segments; index++) {
        const double t = (double)index / (double)segments;
        const double angle = start_angle + sweep * t;
        SiteKeeperLibreDWGPoint point = {
            center_x + cos(angle) * radius,
            center_y + sin(angle) * radius
        };
        if (!sitekeeper_push_polyline_point(points, point_count, point_capacity, point)) {
            return 0;
        }
    }
    return 1;
}

static SiteKeeperLibreDWGPoint sitekeeper_point_from_3bd(BITCODE_3BD point)
{
    SiteKeeperLibreDWGPoint out;
    out.x = point.x;
    out.y = point.y;
    return out;
}

static int sitekeeper_append_point(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.POINT == NULL) {
        return 0;
    }

    Dwg_Entity_POINT *point = entity->tio.POINT;
    if (!isfinite(point->x) || !isfinite(point->y)) {
        return 0;
    }

    const double marker_size = 0.5;
    SiteKeeperLibreDWGPoint points[2] = {
        { point->x - marker_size, point->y },
        { point->x + marker_size, point->y }
    };
    return sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindPoint,
        points,
        2,
        0,
        transform
    );
}

static int sitekeeper_append_ray_or_xline(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    int32_t kind,
    const SiteKeeperLibreDWGTransform *transform
)
{
    Dwg_Entity_RAY *ray = kind == SiteKeeperLibreDWGEntityKindXLine
        ? (Dwg_Entity_RAY *)entity->tio.XLINE
        : entity->tio.RAY;
    if (ray == NULL) {
        return 0;
    }

    const double vector_length = hypot(ray->vector.x, ray->vector.y);
    if (!isfinite(ray->point.x) || !isfinite(ray->point.y)
        || !isfinite(vector_length) || vector_length <= DBL_EPSILON) {
        return 0;
    }

    const double dx = ray->vector.x / vector_length;
    const double dy = ray->vector.y / vector_length;
    const double length = 100000.0;
    SiteKeeperLibreDWGPoint points[2];
    if (kind == SiteKeeperLibreDWGEntityKindXLine) {
        points[0].x = ray->point.x - dx * length;
        points[0].y = ray->point.y - dy * length;
        points[1].x = ray->point.x + dx * length;
        points[1].y = ray->point.y + dy * length;
    } else {
        points[0].x = ray->point.x;
        points[0].y = ray->point.y;
        points[1].x = ray->point.x + dx * length;
        points[1].y = ray->point.y + dy * length;
    }
    return sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        kind,
        points,
        2,
        0,
        transform
    );
}

static SiteKeeperLibreDWGPoint *sitekeeper_make_ellipse_points(
    double center_x,
    double center_y,
    double major_axis_x,
    double major_axis_y,
    double axis_ratio,
    double start_angle,
    double end_angle,
    int32_t *point_count,
    int32_t *is_closed
)
{
    if (point_count == NULL || is_closed == NULL) {
        return NULL;
    }
    *point_count = 0;
    *is_closed = 0;

    const double major_radius = hypot(major_axis_x, major_axis_y);
    if (!isfinite(center_x) || !isfinite(center_y) || !isfinite(major_radius)
        || major_radius <= DBL_EPSILON || !isfinite(axis_ratio) || axis_ratio <= DBL_EPSILON) {
        return NULL;
    }

    if (!isfinite(start_angle)) {
        start_angle = 0;
    }
    if (!isfinite(end_angle)) {
        end_angle = SITEKEEPER_PI * 2.0;
    }
    while (end_angle < start_angle) {
        end_angle += SITEKEEPER_PI * 2.0;
    }

    double sweep = end_angle - start_angle;
    if (sweep <= 0.000001) {
        sweep = SITEKEEPER_PI * 2.0;
    }
    *is_closed = fabs(sweep - SITEKEEPER_PI * 2.0) < 0.0001 || sweep >= SITEKEEPER_PI * 2.0;

    int32_t segments = (int32_t)ceil(fabs(sweep) / (SITEKEEPER_PI / 32.0));
    if (segments < 16) {
        segments = 16;
    }
    if (segments > 128) {
        segments = 128;
    }
    *point_count = *is_closed ? segments : segments + 1;

    SiteKeeperLibreDWGPoint *points = (SiteKeeperLibreDWGPoint *)calloc(
        (size_t)*point_count,
        sizeof(SiteKeeperLibreDWGPoint)
    );
    if (points == NULL) {
        *point_count = 0;
        return NULL;
    }

    const double rotation = atan2(major_axis_y, major_axis_x);
    const double cos_rotation = cos(rotation);
    const double sin_rotation = sin(rotation);
    const double minor_radius = major_radius * axis_ratio;
    const double divisor = (double)segments;

    for (int32_t index = 0; index < *point_count; index++) {
        const double t = (double)index / divisor;
        const double parameter = start_angle + sweep * t;
        const double local_x = cos(parameter) * major_radius;
        const double local_y = sin(parameter) * minor_radius;
        points[index].x = center_x + local_x * cos_rotation - local_y * sin_rotation;
        points[index].y = center_y + local_x * sin_rotation + local_y * cos_rotation;
    }
    return points;
}

static int sitekeeper_append_line(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.LINE == NULL) {
        return 0;
    }

    Dwg_Entity_LINE *line = entity->tio.LINE;
    SiteKeeperLibreDWGPoint points[2] = {
        { line->start.x, line->start.y },
        { line->end.x, line->end.y }
    };
    if (!isfinite(points[0].x) || !isfinite(points[0].y) || !isfinite(points[1].x) || !isfinite(points[1].y)) {
        return 0;
    }
    if (sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindLine,
        points,
        2,
        0,
        transform
    )) {
        result->trace.exportedLineCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_lwpolyline(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.LWPOLYLINE == NULL) {
        return 0;
    }

    int error = 0;
    Dwg_Entity_LWPOLYLINE *pline = entity->tio.LWPOLYLINE;
    BITCODE_BL num_points = dwg_ent_lwpline_get_numpoints(pline, &error);
    if (error || num_points < 2) {
        return 0;
    }

    dwg_point_2d *raw_points = dwg_ent_lwpline_get_points(pline, &error);
    if (error || raw_points == NULL) {
        free(raw_points);
        return 0;
    }

    int bulge_error = 0;
    double *bulges = dwg_ent_lwpline_get_bulges(pline, &bulge_error);
    if (bulge_error) {
        free(bulges);
        bulges = NULL;
    }

    SiteKeeperLibreDWGPoint *points = NULL;
    int32_t point_count = 0;
    int32_t point_capacity = 0;
    SiteKeeperLibreDWGPoint first = { raw_points[0].x, raw_points[0].y };
    if (!sitekeeper_push_polyline_point(&points, &point_count, &point_capacity, first)) {
        free(raw_points);
        free(bulges);
        return 0;
    }

    for (BITCODE_BL index = 0; index + 1 < num_points; index++) {
        SiteKeeperLibreDWGPoint start = { raw_points[index].x, raw_points[index].y };
        SiteKeeperLibreDWGPoint end = { raw_points[index + 1].x, raw_points[index + 1].y };
        double bulge = (bulges != NULL && index < pline->num_bulges) ? bulges[index] : 0;
        if (!sitekeeper_append_bulge_segment_points(&points, &point_count, &point_capacity, start, end, bulge)) {
            free(raw_points);
            free(bulges);
            free(points);
            return 0;
        }
    }
    if ((pline->flag & FLAG_LWPOLYLINE_CLOSED) != 0 && num_points > 2) {
        SiteKeeperLibreDWGPoint start = { raw_points[num_points - 1].x, raw_points[num_points - 1].y };
        SiteKeeperLibreDWGPoint end = { raw_points[0].x, raw_points[0].y };
        double bulge = (bulges != NULL && (num_points - 1) < pline->num_bulges) ? bulges[num_points - 1] : 0;
        if (!sitekeeper_append_bulge_segment_points(&points, &point_count, &point_capacity, start, end, bulge)) {
            free(raw_points);
            free(bulges);
            free(points);
            return 0;
        }
    }
    free(raw_points);
    free(bulges);

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindLWPolyline,
        points,
        point_count,
        (pline->flag & FLAG_LWPOLYLINE_CLOSED) != 0,
        transform
    );
    free(points);
    if (appended) {
        result->trace.exportedPolylineCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_polyline_2d(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.POLYLINE_2D == NULL) {
        return 0;
    }

    int error = 0;
    Dwg_Entity_POLYLINE_2D *pline = entity->tio.POLYLINE_2D;
    BITCODE_BL num_points = dwg_object_polyline_2d_get_numpoints(object, &error);
    if (error || num_points < 2) {
        return 0;
    }

    dwg_point_2d *raw_points = dwg_object_polyline_2d_get_points(object, &error);
    if (error || raw_points == NULL) {
        free(raw_points);
        return 0;
    }

    SiteKeeperLibreDWGPoint *points = (SiteKeeperLibreDWGPoint *)calloc(
        (size_t)num_points,
        sizeof(SiteKeeperLibreDWGPoint)
    );
    if (points == NULL) {
        free(raw_points);
        return 0;
    }

    for (BITCODE_BL index = 0; index < num_points; index++) {
        points[index].x = raw_points[index].x;
        points[index].y = raw_points[index].y;
    }
    free(raw_points);

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindPolyline,
        points,
        (int32_t)num_points,
        (pline->flag & FLAG_POLYLINE_CLOSED) != 0,
        transform
    );
    free(points);
    if (appended) {
        result->trace.exportedPolylineCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_polyline_3d(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.POLYLINE_3D == NULL) {
        return 0;
    }

    int error = 0;
    Dwg_Entity_POLYLINE_3D *pline = entity->tio.POLYLINE_3D;
    BITCODE_BL num_points = dwg_object_polyline_3d_get_numpoints(object, &error);
    if (error || num_points < 2) {
        return 0;
    }

    dwg_point_3d *raw_points = dwg_object_polyline_3d_get_points(object, &error);
    if (error || raw_points == NULL) {
        free(raw_points);
        return 0;
    }

    SiteKeeperLibreDWGPoint *points = (SiteKeeperLibreDWGPoint *)calloc(
        (size_t)num_points,
        sizeof(SiteKeeperLibreDWGPoint)
    );
    if (points == NULL) {
        free(raw_points);
        return 0;
    }

    for (BITCODE_BL index = 0; index < num_points; index++) {
        points[index].x = raw_points[index].x;
        points[index].y = raw_points[index].y;
    }
    free(raw_points);

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindPolyline,
        points,
        (int32_t)num_points,
        (pline->flag & FLAG_POLYLINE_CLOSED) != 0,
        transform
    );
    free(points);
    if (appended) {
        result->trace.exportedPolylineCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_circle(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.CIRCLE == NULL) {
        return 0;
    }

    Dwg_Entity_CIRCLE *circle = entity->tio.CIRCLE;
    if (!isfinite(circle->center.x) || !isfinite(circle->center.y) || !isfinite(circle->radius)) {
        return 0;
    }

    int32_t point_count = 0;
    SiteKeeperLibreDWGPoint *points = sitekeeper_make_circle_points(
        circle->center.x,
        circle->center.y,
        circle->radius,
        &point_count
    );
    if (points == NULL) {
        return 0;
    }

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindCircle,
        points,
        point_count,
        1,
        transform
    );
    free(points);
    if (appended) {
        result->trace.exportedCircleCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_arc(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.ARC == NULL) {
        return 0;
    }

    Dwg_Entity_ARC *arc = entity->tio.ARC;
    if (!isfinite(arc->center.x) || !isfinite(arc->center.y) || !isfinite(arc->radius)
        || !isfinite(arc->start_angle) || !isfinite(arc->end_angle)) {
        return 0;
    }

    int32_t point_count = 0;
    SiteKeeperLibreDWGPoint *points = sitekeeper_make_arc_points(
        arc->center.x,
        arc->center.y,
        arc->radius,
        arc->start_angle,
        arc->end_angle,
        &point_count
    );
    if (points == NULL) {
        return 0;
    }

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindArc,
        points,
        point_count,
        0,
        transform
    );
    free(points);
    if (appended) {
        result->trace.exportedArcCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_ellipse(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.ELLIPSE == NULL) {
        return 0;
    }

    Dwg_Entity_ELLIPSE *ellipse = entity->tio.ELLIPSE;
    int32_t point_count = 0;
    int32_t is_closed = 0;
    SiteKeeperLibreDWGPoint *points = sitekeeper_make_ellipse_points(
        ellipse->center.x,
        ellipse->center.y,
        ellipse->sm_axis.x,
        ellipse->sm_axis.y,
        ellipse->axis_ratio,
        ellipse->start_angle,
        ellipse->end_angle,
        &point_count,
        &is_closed
    );
    if (points == NULL) {
        return 0;
    }

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindEllipse,
        points,
        point_count,
        is_closed,
        transform
    );
    free(points);
    if (appended) {
        result->trace.exportedEllipseCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_spline(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.SPLINE == NULL) {
        return 0;
    }

    Dwg_Entity_SPLINE *spline = entity->tio.SPLINE;
    int32_t point_count = 0;
    SiteKeeperLibreDWGPoint *points = NULL;
    if (spline->fit_pts != NULL && spline->num_fit_pts >= 2) {
        point_count = (int32_t)spline->num_fit_pts;
        points = (SiteKeeperLibreDWGPoint *)calloc((size_t)point_count, sizeof(SiteKeeperLibreDWGPoint));
        if (points == NULL) {
            return 0;
        }
        for (int32_t index = 0; index < point_count; index++) {
            points[index].x = spline->fit_pts[index].x;
            points[index].y = spline->fit_pts[index].y;
        }
    } else if (spline->ctrl_pts != NULL && spline->num_ctrl_pts >= 2) {
        point_count = (int32_t)spline->num_ctrl_pts;
        points = (SiteKeeperLibreDWGPoint *)calloc((size_t)point_count, sizeof(SiteKeeperLibreDWGPoint));
        if (points == NULL) {
            return 0;
        }
        for (int32_t index = 0; index < point_count; index++) {
            points[index].x = spline->ctrl_pts[index].x;
            points[index].y = spline->ctrl_pts[index].y;
        }
    }

    if (points == NULL || point_count < 2) {
        free(points);
        return 0;
    }

    const int32_t is_closed = spline->closed_b != 0 || (spline->splineflags & SPLINE_SPLINEFLAGS_CLOSED) != 0;
    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindSpline,
        points,
        point_count,
        is_closed,
        transform
    );
    free(points);
    if (appended) {
        result->trace.exportedSplineCount += 1;
        return 1;
    }
    return 0;
}

static int32_t sitekeeper_unique_shape_points(
    const SiteKeeperLibreDWGPoint *input,
    int32_t input_count,
    SiteKeeperLibreDWGPoint *output
)
{
    if (input == NULL || output == NULL || input_count <= 0) {
        return 0;
    }

    int32_t output_count = 0;
    for (int32_t index = 0; index < input_count; index++) {
        SiteKeeperLibreDWGPoint point = input[index];
        if (!isfinite(point.x) || !isfinite(point.y)) {
            continue;
        }

        int duplicate = 0;
        for (int32_t existing = 0; existing < output_count; existing++) {
            if (fabs(output[existing].x - point.x) < 0.000001
                && fabs(output[existing].y - point.y) < 0.000001) {
                duplicate = 1;
                break;
            }
        }
        if (!duplicate) {
            output[output_count] = point;
            output_count += 1;
        }
    }
    return output_count;
}

static int sitekeeper_append_filled_shape_points(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGPoint *raw_points,
    int32_t raw_point_count,
    const SiteKeeperLibreDWGTransform *transform
)
{
    SiteKeeperLibreDWGPoint points[4];
    const int32_t point_count = sitekeeper_unique_shape_points(raw_points, raw_point_count, points);
    if (point_count < 3) {
        return 0;
    }

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindFilledShape,
        points,
        point_count,
        1,
        transform
    );
    if (appended) {
        result->trace.exportedFilledShapeCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_solid(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.SOLID == NULL) {
        return 0;
    }
    Dwg_Entity_SOLID *solid = entity->tio.SOLID;
    SiteKeeperLibreDWGPoint points[4] = {
        { solid->corner1.x, solid->corner1.y },
        { solid->corner2.x, solid->corner2.y },
        { solid->corner3.x, solid->corner3.y },
        { solid->corner4.x, solid->corner4.y }
    };
    return sitekeeper_append_filled_shape_points(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        points,
        4,
        transform
    );
}

static int sitekeeper_append_trace(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.TRACE == NULL) {
        return 0;
    }
    Dwg_Entity_TRACE *trace = entity->tio.TRACE;
    SiteKeeperLibreDWGPoint points[4] = {
        { trace->corner1.x, trace->corner1.y },
        { trace->corner2.x, trace->corner2.y },
        { trace->corner3.x, trace->corner3.y },
        { trace->corner4.x, trace->corner4.y }
    };
    return sitekeeper_append_filled_shape_points(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        points,
        4,
        transform
    );
}

static int sitekeeper_append_3dface(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio._3DFACE == NULL) {
        return 0;
    }
    Dwg_Entity__3DFACE *face = entity->tio._3DFACE;
    SiteKeeperLibreDWGPoint points[4] = {
        { face->corner1.x, face->corner1.y },
        { face->corner2.x, face->corner2.y },
        { face->corner3.x, face->corner3.y },
        { face->corner4.x, face->corner4.y }
    };
    return sitekeeper_append_filled_shape_points(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        points,
        4,
        transform
    );
}

static int sitekeeper_append_leader(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.LEADER == NULL || entity->tio.LEADER->points == NULL || entity->tio.LEADER->num_points < 2) {
        return 0;
    }

    Dwg_Entity_LEADER *leader = entity->tio.LEADER;
    const int32_t point_count = (int32_t)leader->num_points;
    SiteKeeperLibreDWGPoint *points = (SiteKeeperLibreDWGPoint *)calloc(
        (size_t)point_count,
        sizeof(SiteKeeperLibreDWGPoint)
    );
    if (points == NULL) {
        return 0;
    }
    for (int32_t index = 0; index < point_count; index++) {
        points[index].x = leader->points[index].x;
        points[index].y = leader->points[index].y;
    }

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindLeader,
        points,
        point_count,
        0,
        transform
    );
    free(points);
    return appended;
}

static int sitekeeper_append_mline(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.MLINE == NULL || entity->tio.MLINE->verts == NULL || entity->tio.MLINE->num_verts < 2) {
        return 0;
    }

    Dwg_Entity_MLINE *mline = entity->tio.MLINE;
    const int32_t point_count = (int32_t)mline->num_verts;
    SiteKeeperLibreDWGPoint *points = (SiteKeeperLibreDWGPoint *)calloc(
        (size_t)point_count,
        sizeof(SiteKeeperLibreDWGPoint)
    );
    if (points == NULL) {
        return 0;
    }
    for (int32_t index = 0; index < point_count; index++) {
        points[index] = sitekeeper_point_from_3bd(mline->verts[index].vertex);
    }

    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindMLine,
        points,
        point_count,
        (mline->flags & 2) != 0,
        transform
    );
    free(points);
    return appended;
}

static int sitekeeper_append_multileader(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.MULTILEADER == NULL) {
        return 0;
    }

    Dwg_Entity_MULTILEADER *mleader = entity->tio.MULTILEADER;
    int appended = 0;
    Dwg_MLEADER_AnnotContext *ctx = &mleader->ctx;

    if (ctx->leaders != NULL) {
        for (BITCODE_BL leader_index = 0; leader_index < ctx->num_leaders; leader_index++) {
            Dwg_LEADER_Node *node = &ctx->leaders[leader_index];
            if (node->lines == NULL) {
                continue;
            }
            for (BITCODE_BL line_index = 0; line_index < node->num_lines; line_index++) {
                Dwg_LEADER_Line *line = &node->lines[line_index];
                if (line->points == NULL || line->num_points < 2) {
                    continue;
                }

                const int32_t point_count = (int32_t)line->num_points;
                SiteKeeperLibreDWGPoint *points = (SiteKeeperLibreDWGPoint *)calloc(
                    (size_t)point_count,
                    sizeof(SiteKeeperLibreDWGPoint)
                );
                if (points == NULL) {
                    continue;
                }
                for (int32_t index = 0; index < point_count; index++) {
                    points[index].x = line->points[index].x;
                    points[index].y = line->points[index].y;
                }
                appended += sitekeeper_append_entity(
                    result,
                    entity_count,
                    entity_capacity,
                    entity,
                    object,
                    SiteKeeperLibreDWGEntityKindLeader,
                    points,
                    point_count,
                    0,
                    transform
                );
                free(points);
            }
        }
    }

    if (ctx->has_content_txt && ctx->content.txt.default_text != NULL && ctx->content.txt.default_text[0] != '\0') {
        Dwg_MLEADER_Content_MText *text = &ctx->content.txt;
        SiteKeeperLibreDWGPoint insertion = { text->location.x, text->location.y };
        if (!sitekeeper_point_is_finite(insertion)) {
            insertion.x = ctx->content_base.x;
            insertion.y = ctx->content_base.y;
        }
        if (!sitekeeper_point_is_finite(insertion)) {
            insertion.x = ctx->base.x;
            insertion.y = ctx->base.y;
        }

        Dwg_Object_STYLE *style = sitekeeper_style_from_ref(entity->dwg, text->style);
        if (style == NULL) {
            style = sitekeeper_style_from_ref(entity->dwg, mleader->text_style);
        }
        const double height = isfinite(text->height) && text->height > DBL_EPSILON
            ? text->height
            : ctx->text_height;
        appended += sitekeeper_append_text_entity(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            SiteKeeperLibreDWGEntityKindMText,
            text->default_text,
            insertion.x,
            insertion.y,
            height,
            text->rotation,
            1.0,
            text->width,
            0,
            text->alignment,
            ctx->text_alignment,
            style,
            transform
        );
    }

    if (mleader->blocklabels != NULL) {
        Dwg_Object_STYLE *style = sitekeeper_style_from_ref(entity->dwg, mleader->text_style);
        for (BITCODE_BL label_index = 0; label_index < mleader->num_blocklabels; label_index++) {
            Dwg_LEADER_BlockLabel *label = &mleader->blocklabels[label_index];
            if (label->label_text == NULL || label->label_text[0] == '\0') {
                continue;
            }
            appended += sitekeeper_append_text_entity(
                result,
                entity_count,
                entity_capacity,
                entity,
                object,
                SiteKeeperLibreDWGEntityKindMText,
                label->label_text,
                ctx->base.x,
                ctx->base.y,
                ctx->text_height,
                0,
                1.0,
                label->width,
                0,
                1,
                2,
                style,
                transform
            );
        }
    }

    return appended;
}

static const char *sitekeeper_table_cell_text(const Dwg_TABLE_Cell *cell)
{
    if (cell == NULL) {
        return NULL;
    }
    if (cell->text_value != NULL && cell->text_value[0] != '\0') {
        return cell->text_value;
    }
    if (cell->value.value_string != NULL && cell->value.value_string[0] != '\0') {
        return cell->value.value_string;
    }
    if (cell->value.data_string != NULL && cell->value.data_string[0] != '\0') {
        return cell->value.data_string;
    }
    if (cell->attr_defs != NULL) {
        for (BITCODE_BL index = 0; index < cell->num_attr_defs; index++) {
            if (cell->attr_defs[index].text != NULL && cell->attr_defs[index].text[0] != '\0') {
                return cell->attr_defs[index].text;
            }
        }
    }
    return NULL;
}

static Dwg_Object_STYLE *sitekeeper_table_cell_style(
    Dwg_Data *dwg,
    Dwg_Entity_TABLE *table,
    Dwg_TABLE_Cell *cell,
    BITCODE_BL row
)
{
    Dwg_Object_STYLE *style = sitekeeper_style_from_ref(dwg, cell != NULL ? cell->text_style : NULL);
    if (style != NULL || table == NULL) {
        return style;
    }
    if (row == 0) {
        style = sitekeeper_style_from_ref(dwg, table->title_text_style);
    } else if (row == 1) {
        style = sitekeeper_style_from_ref(dwg, table->header_text_style);
    }
    if (style == NULL) {
        style = sitekeeper_style_from_ref(dwg, table->data_text_style);
    }
    return style;
}

static double sitekeeper_table_column_width(Dwg_Entity_TABLE *table, BITCODE_BL column)
{
    if (table != NULL && table->col_widths != NULL && column < table->num_cols
        && isfinite(table->col_widths[column]) && table->col_widths[column] > DBL_EPSILON) {
        return table->col_widths[column];
    }
    return 20.0;
}

static double sitekeeper_table_row_height(Dwg_Entity_TABLE *table, BITCODE_BL row)
{
    if (table != NULL && table->row_heights != NULL && row < table->num_rows
        && isfinite(table->row_heights[row]) && table->row_heights[row] > DBL_EPSILON) {
        return table->row_heights[row];
    }
    if (table != NULL) {
        if (row == 0 && isfinite(table->title_row_height) && table->title_row_height > DBL_EPSILON) {
            return table->title_row_height;
        }
        if (row == 1 && isfinite(table->header_row_height) && table->header_row_height > DBL_EPSILON) {
            return table->header_row_height;
        }
        if (isfinite(table->data_row_height) && table->data_row_height > DBL_EPSILON) {
            return table->data_row_height;
        }
    }
    return 8.0;
}

static double sitekeeper_table_text_height(Dwg_Entity_TABLE *table, Dwg_TABLE_Cell *cell, BITCODE_BL row)
{
    if (cell != NULL && isfinite(cell->text_height) && cell->text_height > DBL_EPSILON) {
        return cell->text_height;
    }
    return fmax(sitekeeper_table_row_height(table, row) * 0.45, 2.5);
}

static int sitekeeper_append_table(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.TABLE == NULL || entity->tio.TABLE->cells == NULL || entity->tio.TABLE->num_cells == 0) {
        return 0;
    }

    Dwg_Entity_TABLE *table = entity->tio.TABLE;
    const BITCODE_BL column_count = table->num_cols > 0 ? table->num_cols : 1;
    const BITCODE_BL row_count = table->num_rows > 0 ? table->num_rows : (BITCODE_BL)((table->num_cells + column_count - 1) / column_count);
    const double rotation = isfinite(table->rotation) ? table->rotation : 0;
    const double cos_angle = cos(rotation);
    const double sin_angle = sin(rotation);
    const double scale_x = isfinite(table->scale.x) && fabs(table->scale.x) > DBL_EPSILON ? table->scale.x : 1;
    const double scale_y = isfinite(table->scale.y) && fabs(table->scale.y) > DBL_EPSILON ? table->scale.y : 1;
    int appended = 0;

    for (unsigned long cell_index = 0; cell_index < table->num_cells; cell_index++) {
        Dwg_TABLE_Cell *cell = &table->cells[cell_index];
        const char *text = sitekeeper_table_cell_text(cell);
        if (text == NULL || text[0] == '\0') {
            continue;
        }

        BITCODE_BL row = (BITCODE_BL)(cell_index / column_count);
        BITCODE_BL column = (BITCODE_BL)(cell_index % column_count);
        if (row >= row_count) {
            row = row_count > 0 ? row_count - 1 : 0;
        }

        double local_x = 0;
        for (BITCODE_BL col = 0; col < column; col++) {
            local_x += sitekeeper_table_column_width(table, col);
        }
        const double cell_width = sitekeeper_table_column_width(table, column);
        local_x += cell_width * 0.08;

        double local_y = 0;
        for (BITCODE_BL current_row = 0; current_row < row; current_row++) {
            local_y -= sitekeeper_table_row_height(table, current_row);
        }
        const double cell_height = sitekeeper_table_row_height(table, row);
        local_y -= cell_height * 0.55;

        const double x = table->ins_pt.x + (local_x * scale_x) * cos_angle - (local_y * scale_y) * sin_angle;
        const double y = table->ins_pt.y + (local_x * scale_x) * sin_angle + (local_y * scale_y) * cos_angle;
        const int32_t before_count = *entity_count;
        int did_append = sitekeeper_append_text_entity(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            SiteKeeperLibreDWGEntityKindMText,
            text,
            x,
            y,
            sitekeeper_table_text_height(table, cell, row),
            rotation + cell->rotation,
            1.0,
            cell_width,
            cell_height,
            cell->cell_alignment,
            cell->cell_alignment,
            sitekeeper_table_cell_style(entity->dwg, table, cell, row),
            transform
        );
        if (did_append) {
            free(result->entities[before_count].sourceHandle);
            result->entities[before_count].sourceHandle = sitekeeper_handle_string_with_suffix(object, cell_index);
            appended += 1;
        }
    }

    return appended;
}

static int sitekeeper_append_image_frame(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    int32_t kind,
    BITCODE_3BD pt0,
    BITCODE_3BD uvec,
    BITCODE_3BD vvec,
    BITCODE_2RD image_size,
    const SiteKeeperLibreDWGTransform *transform
)
{
    double width = image_size.x;
    double height = image_size.y;
    if (!isfinite(width) || width <= DBL_EPSILON) {
        width = 1;
    }
    if (!isfinite(height) || height <= DBL_EPSILON) {
        height = 1;
    }
    if (!isfinite(pt0.x) || !isfinite(pt0.y)
        || !isfinite(uvec.x) || !isfinite(uvec.y)
        || !isfinite(vvec.x) || !isfinite(vvec.y)) {
        return 0;
    }

    SiteKeeperLibreDWGPoint points[4] = {
        { pt0.x, pt0.y },
        { pt0.x + uvec.x * width, pt0.y + uvec.y * width },
        { pt0.x + uvec.x * width + vvec.x * height, pt0.y + uvec.y * width + vvec.y * height },
        { pt0.x + vvec.x * height, pt0.y + vvec.y * height }
    };
    return sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        kind,
        points,
        4,
        1,
        transform
    );
}

static int sitekeeper_append_image(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.IMAGE == NULL) {
        return 0;
    }
    Dwg_Entity_IMAGE *image = entity->tio.IMAGE;
    return sitekeeper_append_image_frame(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindImage,
        image->pt0,
        image->uvec,
        image->vvec,
        image->image_size,
        transform
    );
}

static int sitekeeper_append_wipeout(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.WIPEOUT == NULL) {
        return 0;
    }
    Dwg_Entity_WIPEOUT *wipeout = entity->tio.WIPEOUT;
    return sitekeeper_append_image_frame(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindWipeout,
        wipeout->pt0,
        wipeout->uvec,
        wipeout->vvec,
        wipeout->image_size,
        transform
    );
}

static int sitekeeper_append_underlay(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    Dwg_Entity_UNDERLAY *underlay,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (underlay == NULL) {
        return 0;
    }

    const double sx = isfinite(underlay->scale.x) && fabs(underlay->scale.x) > DBL_EPSILON ? underlay->scale.x : 1;
    const double sy = isfinite(underlay->scale.y) && fabs(underlay->scale.y) > DBL_EPSILON ? underlay->scale.y : 1;
    const double angle = isfinite(underlay->angle) ? underlay->angle : 0;
    const double cos_angle = cos(angle);
    const double sin_angle = sin(angle);
    SiteKeeperLibreDWGPoint local[4] = {
        { 0, 0 },
        { sx, 0 },
        { sx, sy },
        { 0, sy }
    };
    SiteKeeperLibreDWGPoint points[4];
    for (int32_t index = 0; index < 4; index++) {
        const double x = local[index].x;
        const double y = local[index].y;
        points[index].x = underlay->ins_pt.x + x * cos_angle - y * sin_angle;
        points[index].y = underlay->ins_pt.y + x * sin_angle + y * cos_angle;
    }
    return sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindUnderlay,
        points,
        4,
        1,
        transform
    );
}

static int sitekeeper_append_text(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.TEXT == NULL) {
        return 0;
    }
    Dwg_Entity_TEXT *text = entity->tio.TEXT;
    Dwg_Object_STYLE *style = sitekeeper_style_from_ref(entity->dwg, text->style);
    return sitekeeper_append_text_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindText,
        text->text_value,
        text->ins_pt.x,
        text->ins_pt.y,
        text->height,
        text->rotation,
        text->width_factor,
        0,
        0,
        text->horiz_alignment,
        text->vert_alignment,
        style,
        transform
    );
}

static int sitekeeper_append_mtext(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.MTEXT == NULL) {
        return 0;
    }
    Dwg_Entity_MTEXT *text = entity->tio.MTEXT;
    const double rotation = atan2(text->x_axis_dir.y, text->x_axis_dir.x);
    Dwg_Object_STYLE *style = sitekeeper_style_from_ref(entity->dwg, text->style);
    return sitekeeper_append_text_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindMText,
        text->text,
        text->ins_pt.x,
        text->ins_pt.y,
        text->text_height,
        rotation,
        1.0,
        text->rect_width > 0 ? text->rect_width : text->extents_width,
        text->rect_height > 0 ? text->rect_height : text->extents_height,
        text->attachment,
        text->attachment,
        style,
        transform
    );
}

static int sitekeeper_append_attrib(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.ATTRIB == NULL) {
        return 0;
    }
    Dwg_Entity_ATTRIB *text = entity->tio.ATTRIB;
    Dwg_Object_STYLE *style = sitekeeper_style_from_ref(entity->dwg, text->style);
    return sitekeeper_append_text_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindAttrib,
        text->text_value,
        text->ins_pt.x,
        text->ins_pt.y,
        text->height,
        text->rotation,
        text->width_factor,
        0,
        0,
        text->horiz_alignment,
        text->vert_alignment,
        style,
        transform
    );
}

static int sitekeeper_append_attdef(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.ATTDEF == NULL) {
        return 0;
    }
    Dwg_Entity_ATTDEF *text = entity->tio.ATTDEF;
    Dwg_Object_STYLE *style = sitekeeper_style_from_ref(entity->dwg, text->style);
    return sitekeeper_append_text_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindAttrib,
        text->default_value,
        text->ins_pt.x,
        text->ins_pt.y,
        text->height,
        text->rotation,
        text->width_factor,
        0,
        0,
        text->horiz_alignment,
        text->vert_alignment,
        style,
        transform
    );
}

static int sitekeeper_append_dimension_path(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    SiteKeeperLibreDWGPoint start,
    SiteKeeperLibreDWGPoint end,
    SiteKeeperLibreDWGPoint text_point,
    SiteKeeperLibreDWGPoint dimension_line_point,
    int has_dimension_line_point,
    double axis_rotation,
    int has_axis_rotation,
    const char *user_text,
    double measurement,
    double text_rotation,
    double text_height,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (!isfinite(start.x) || !isfinite(start.y) || !isfinite(end.x) || !isfinite(end.y)) {
        return 0;
    }

    const int has_text_point = sitekeeper_point_is_finite(text_point);
    SiteKeeperLibreDWGPoint points[4];
    const int32_t point_count = sitekeeper_make_dimension_display_points(
        start,
        end,
        dimension_line_point,
        has_dimension_line_point,
        text_point,
        has_text_point,
        axis_rotation,
        has_axis_rotation,
        points,
        4
    );
    if (point_count < 2) {
        return 0;
    }
    const int32_t before_count = *entity_count;
    if (!sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindDimension,
        points,
        point_count,
        0,
        transform
    )) {
        return 0;
    }

    char text_buffer[256];
    const char *raw_text = sitekeeper_dimension_text(
        user_text,
        measurement,
        text_buffer,
        sizeof(text_buffer)
    );
    sitekeeper_attach_text_to_entity(
        result,
        before_count,
        raw_text,
        text_point.x,
        text_point.y,
        text_height,
        text_rotation,
        1.0,
        1,
        2,
        NULL,
        transform
    );
    result->trace.exportedDimensionCount += 1;
    return 1;
}

static int sitekeeper_append_dimension_linear(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.DIMENSION_LINEAR == NULL) {
        return 0;
    }
    Dwg_Entity_DIMENSION_LINEAR *dimension = entity->tio.DIMENSION_LINEAR;
    SiteKeeperLibreDWGPoint start = { dimension->xline1_pt.x, dimension->xline1_pt.y };
    SiteKeeperLibreDWGPoint end = { dimension->xline2_pt.x, dimension->xline2_pt.y };
    SiteKeeperLibreDWGPoint text_point = { dimension->text_midpt.x, dimension->text_midpt.y };
    SiteKeeperLibreDWGPoint dimension_line_point = { dimension->def_pt.x, dimension->def_pt.y };
    Dwg_Object_DIMSTYLE *dimstyle = sitekeeper_dimstyle_from_ref(entity->dwg, dimension->dimstyle);
    if (!isfinite(text_point.x) || !isfinite(text_point.y)) {
        text_point.x = (start.x + end.x) / 2.0;
        text_point.y = (start.y + end.y) / 2.0;
    }
    return sitekeeper_append_dimension_path(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        start,
        end,
        text_point,
        dimension_line_point,
        sitekeeper_point_is_finite(dimension_line_point),
        dimension->dim_rotation,
        1,
        dimension->user_text,
        dimension->act_measurement,
        dimension->text_rotation,
        sitekeeper_dimstyle_text_height(dimstyle),
        transform
    );
}

static int sitekeeper_append_dimension_aligned(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.DIMENSION_ALIGNED == NULL) {
        return 0;
    }
    Dwg_Entity_DIMENSION_ALIGNED *dimension = entity->tio.DIMENSION_ALIGNED;
    SiteKeeperLibreDWGPoint start = { dimension->xline1_pt.x, dimension->xline1_pt.y };
    SiteKeeperLibreDWGPoint end = { dimension->xline2_pt.x, dimension->xline2_pt.y };
    SiteKeeperLibreDWGPoint text_point = { dimension->text_midpt.x, dimension->text_midpt.y };
    SiteKeeperLibreDWGPoint dimension_line_point = { dimension->def_pt.x, dimension->def_pt.y };
    Dwg_Object_DIMSTYLE *dimstyle = sitekeeper_dimstyle_from_ref(entity->dwg, dimension->dimstyle);
    if (!isfinite(text_point.x) || !isfinite(text_point.y)) {
        text_point.x = (start.x + end.x) / 2.0;
        text_point.y = (start.y + end.y) / 2.0;
    }
    return sitekeeper_append_dimension_path(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        start,
        end,
        text_point,
        dimension_line_point,
        sitekeeper_point_is_finite(dimension_line_point),
        0,
        0,
        dimension->user_text,
        dimension->act_measurement,
        dimension->text_rotation,
        sitekeeper_dimstyle_text_height(dimstyle),
        transform
    );
}

static int sitekeeper_append_dimension_radius(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.DIMENSION_RADIUS == NULL) {
        return 0;
    }
    Dwg_Entity_DIMENSION_RADIUS *dimension = entity->tio.DIMENSION_RADIUS;
    SiteKeeperLibreDWGPoint start = { dimension->first_arc_pt.x, dimension->first_arc_pt.y };
    SiteKeeperLibreDWGPoint end = { dimension->def_pt.x, dimension->def_pt.y };
    SiteKeeperLibreDWGPoint text_point = { dimension->text_midpt.x, dimension->text_midpt.y };
    Dwg_Object_DIMSTYLE *dimstyle = sitekeeper_dimstyle_from_ref(entity->dwg, dimension->dimstyle);
    if (!isfinite(text_point.x) || !isfinite(text_point.y)) {
        text_point.x = (start.x + end.x) / 2.0;
        text_point.y = (start.y + end.y) / 2.0;
    }
    return sitekeeper_append_dimension_path(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        start,
        end,
        text_point,
        end,
        0,
        0,
        0,
        dimension->user_text,
        dimension->act_measurement,
        dimension->text_rotation,
        sitekeeper_dimstyle_text_height(dimstyle),
        transform
    );
}

static int sitekeeper_append_dimension_diameter(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.DIMENSION_DIAMETER == NULL) {
        return 0;
    }
    Dwg_Entity_DIMENSION_DIAMETER *dimension = entity->tio.DIMENSION_DIAMETER;
    SiteKeeperLibreDWGPoint start = { dimension->first_arc_pt.x, dimension->first_arc_pt.y };
    SiteKeeperLibreDWGPoint end = { dimension->def_pt.x, dimension->def_pt.y };
    SiteKeeperLibreDWGPoint text_point = { dimension->text_midpt.x, dimension->text_midpt.y };
    Dwg_Object_DIMSTYLE *dimstyle = sitekeeper_dimstyle_from_ref(entity->dwg, dimension->dimstyle);
    if (!isfinite(text_point.x) || !isfinite(text_point.y)) {
        text_point.x = (start.x + end.x) / 2.0;
        text_point.y = (start.y + end.y) / 2.0;
    }
    return sitekeeper_append_dimension_path(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        start,
        end,
        text_point,
        end,
        0,
        0,
        0,
        dimension->user_text,
        dimension->act_measurement,
        dimension->text_rotation,
        sitekeeper_dimstyle_text_height(dimstyle),
        transform
    );
}

static int sitekeeper_append_dimension_ordinate(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.DIMENSION_ORDINATE == NULL) {
        return 0;
    }
    Dwg_Entity_DIMENSION_ORDINATE *dimension = entity->tio.DIMENSION_ORDINATE;
    SiteKeeperLibreDWGPoint start = { dimension->feature_location_pt.x, dimension->feature_location_pt.y };
    SiteKeeperLibreDWGPoint end = { dimension->leader_endpt.x, dimension->leader_endpt.y };
    SiteKeeperLibreDWGPoint text_point = { dimension->text_midpt.x, dimension->text_midpt.y };
    Dwg_Object_DIMSTYLE *dimstyle = sitekeeper_dimstyle_from_ref(entity->dwg, dimension->dimstyle);
    if (!isfinite(text_point.x) || !isfinite(text_point.y)) {
        text_point.x = end.x;
        text_point.y = end.y;
    }
    return sitekeeper_append_dimension_path(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        start,
        end,
        text_point,
        end,
        1,
        0,
        0,
        dimension->user_text,
        dimension->act_measurement,
        dimension->text_rotation,
        sitekeeper_dimstyle_text_height(dimstyle),
        transform
    );
}

static int sitekeeper_append_dimension_ang3pt(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.DIMENSION_ANG3PT == NULL) {
        return 0;
    }
    Dwg_Entity_DIMENSION_ANG3PT *dimension = entity->tio.DIMENSION_ANG3PT;
    SiteKeeperLibreDWGPoint start = { dimension->xline1_pt.x, dimension->xline1_pt.y };
    SiteKeeperLibreDWGPoint end = { dimension->xline2_pt.x, dimension->xline2_pt.y };
    SiteKeeperLibreDWGPoint text_point = { dimension->text_midpt.x, dimension->text_midpt.y };
    SiteKeeperLibreDWGPoint dimension_line_point = { dimension->def_pt.x, dimension->def_pt.y };
    Dwg_Object_DIMSTYLE *dimstyle = sitekeeper_dimstyle_from_ref(entity->dwg, dimension->dimstyle);
    if (!isfinite(text_point.x) || !isfinite(text_point.y)) {
        text_point = sitekeeper_midpoint(start, end);
    }
    return sitekeeper_append_dimension_path(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        start,
        end,
        text_point,
        dimension_line_point,
        sitekeeper_point_is_finite(dimension_line_point),
        0,
        0,
        dimension->user_text,
        dimension->act_measurement,
        dimension->text_rotation,
        sitekeeper_dimstyle_text_height(dimstyle),
        transform
    );
}

static int sitekeeper_append_dimension_ang2ln(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.DIMENSION_ANG2LN == NULL) {
        return 0;
    }
    Dwg_Entity_DIMENSION_ANG2LN *dimension = entity->tio.DIMENSION_ANG2LN;
    SiteKeeperLibreDWGPoint start = { dimension->xline1end_pt.x, dimension->xline1end_pt.y };
    SiteKeeperLibreDWGPoint end = { dimension->xline2end_pt.x, dimension->xline2end_pt.y };
    SiteKeeperLibreDWGPoint text_point = { dimension->text_midpt.x, dimension->text_midpt.y };
    SiteKeeperLibreDWGPoint dimension_line_point = { dimension->def_pt.x, dimension->def_pt.y };
    Dwg_Object_DIMSTYLE *dimstyle = sitekeeper_dimstyle_from_ref(entity->dwg, dimension->dimstyle);
    if (!isfinite(text_point.x) || !isfinite(text_point.y)) {
        text_point = sitekeeper_midpoint(start, end);
    }
    return sitekeeper_append_dimension_path(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        start,
        end,
        text_point,
        dimension_line_point,
        sitekeeper_point_is_finite(dimension_line_point),
        0,
        0,
        dimension->user_text,
        dimension->act_measurement,
        dimension->text_rotation,
        sitekeeper_dimstyle_text_height(dimstyle),
        transform
    );
}

static int sitekeeper_push_hatch_point(
    SiteKeeperLibreDWGPoint **points,
    int32_t *point_count,
    int32_t *point_capacity,
    SiteKeeperLibreDWGPoint point
)
{
    if (points == NULL || point_count == NULL || point_capacity == NULL) {
        return 0;
    }
    if (!isfinite(point.x) || !isfinite(point.y)) {
        return 1;
    }
    if (*point_count > 0) {
        SiteKeeperLibreDWGPoint previous = (*points)[*point_count - 1];
        if (fabs(previous.x - point.x) < 0.000001 && fabs(previous.y - point.y) < 0.000001) {
            return 1;
        }
    }
    if (*point_count >= *point_capacity) {
        int32_t next_capacity = *point_capacity > 0 ? *point_capacity * 2 : 16;
        SiteKeeperLibreDWGPoint *next_points = (SiteKeeperLibreDWGPoint *)realloc(
            *points,
            sizeof(SiteKeeperLibreDWGPoint) * (size_t)next_capacity
        );
        if (next_points == NULL) {
            return 0;
        }
        *points = next_points;
        *point_capacity = next_capacity;
    }
    (*points)[*point_count] = point;
    *point_count += 1;
    return 1;
}

static int sitekeeper_collect_hatch_segment_points(
    Dwg_HATCH_Path *path,
    SiteKeeperLibreDWGPoint **points,
    int32_t *point_count
)
{
    if (path == NULL || path->segs == NULL || path->num_segs_or_paths <= 0) {
        return 0;
    }

    int32_t point_capacity = 0;
    *points = NULL;
    *point_count = 0;
    for (BITCODE_BL index = 0; index < path->num_segs_or_paths; index++) {
        Dwg_HATCH_PathSeg *segment = &path->segs[index];
        if (segment->curve_type == 1) {
            SiteKeeperLibreDWGPoint start = {
                segment->first_endpoint.x,
                segment->first_endpoint.y
            };
            SiteKeeperLibreDWGPoint end = {
                segment->second_endpoint.x,
                segment->second_endpoint.y
            };
            if (*point_count == 0
                && !sitekeeper_push_hatch_point(points, point_count, &point_capacity, start)) {
                free(*points);
                *points = NULL;
                *point_count = 0;
                return 0;
            }
            if (!sitekeeper_push_hatch_point(points, point_count, &point_capacity, end)) {
                free(*points);
                *points = NULL;
                *point_count = 0;
                return 0;
            }
        } else if (segment->curve_type == 2 && isfinite(segment->radius) && segment->radius > 0) {
            int32_t arc_point_count = 0;
            SiteKeeperLibreDWGPoint *arc_points = sitekeeper_make_arc_points(
                segment->center.x,
                segment->center.y,
                segment->radius,
                segment->start_angle,
                segment->end_angle,
                &arc_point_count
            );
            if (arc_points == NULL) {
                continue;
            }
            for (int32_t arc_index = 0; arc_index < arc_point_count; arc_index++) {
                if (!sitekeeper_push_hatch_point(points, point_count, &point_capacity, arc_points[arc_index])) {
                    free(arc_points);
                    free(*points);
                    *points = NULL;
                    *point_count = 0;
                    return 0;
                }
            }
            free(arc_points);
        }
    }
    return *point_count >= 3;
}

static int sitekeeper_append_hatch_path(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    Dwg_HATCH_Path *path,
    int32_t hatch_path_count,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (path == NULL || path->num_segs_or_paths < 3) {
        return 0;
    }

    SiteKeeperLibreDWGPoint *points = NULL;
    int32_t point_count = 0;
    int closed = path->closed != 0 || (path->flag & 0x20) == 0;
    int is_polyline_path = (path->flag & 2) != 0 && path->polyline_paths != NULL;
    if (is_polyline_path) {
        point_count = (int32_t)path->num_segs_or_paths;
        points = (SiteKeeperLibreDWGPoint *)calloc((size_t)point_count, sizeof(SiteKeeperLibreDWGPoint));
        if (points == NULL) {
            return 0;
        }
        for (int32_t index = 0; index < point_count; index++) {
            points[index].x = path->polyline_paths[index].point.x;
            points[index].y = path->polyline_paths[index].point.y;
        }
    } else if (!sitekeeper_collect_hatch_segment_points(path, &points, &point_count)) {
        free(points);
        return 0;
    }

    int fill_mode = hatch_path_count == 1
        && is_polyline_path
        && path->bulges_present == 0
        && closed
        && point_count <= SITEKEEPER_MAX_FILLED_HATCH_POINTS;
    const int32_t before_count = *entity_count;
    int appended = sitekeeper_append_entity(
        result,
        entity_count,
        entity_capacity,
        entity,
        object,
        SiteKeeperLibreDWGEntityKindHatch,
        points,
        point_count,
        closed,
        transform
    );
    free(points);
    if (appended) {
        result->entities[before_count].hatchFillMode = fill_mode ? 1 : 0;
        result->trace.exportedHatchCount += 1;
        return 1;
    }
    return 0;
}

static int sitekeeper_append_hatch(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    const SiteKeeperLibreDWGTransform *transform
)
{
    if (entity->tio.HATCH == NULL || entity->tio.HATCH->paths == NULL || entity->tio.HATCH->num_paths <= 0) {
        return 0;
    }

    Dwg_Entity_HATCH *hatch = entity->tio.HATCH;
    int exported_count = 0;
    for (BITCODE_BL index = 0; index < hatch->num_paths; index++) {
        exported_count += sitekeeper_append_hatch_path(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            &hatch->paths[index],
            (int32_t)hatch->num_paths,
            transform
        );
    }
    return exported_count;
}

static int sitekeeper_is_insert_object(const Dwg_Object *object)
{
    return sitekeeper_object_matches(object, (int)DWG_TYPE_INSERT)
        || sitekeeper_object_matches(object, (int)DWG_TYPE_MINSERT)
        || sitekeeper_object_matches(object, (int)DWG_TYPE_INSERT_r11);
}

static int sitekeeper_is_top_level_entity(const Dwg_Object_Entity *entity)
{
    return entity != NULL && entity->entmode != 3;
}

static double sitekeeper_insert_scale(double value)
{
    if (!isfinite(value) || fabs(value) < DBL_EPSILON) {
        return 1.0;
    }
    return value;
}

static int32_t sitekeeper_insert_count(long value)
{
    if (value <= 0) {
        return 1;
    }
    if (value > 2048) {
        return 2048;
    }
    return (int32_t)value;
}

static double sitekeeper_insert_spacing(double value)
{
    return isfinite(value) ? value : 0.0;
}

static Dwg_Object_BLOCK_HEADER *sitekeeper_block_header_for_insert(
    Dwg_Data *dwg,
    Dwg_Entity_INSERT *insert,
    Dwg_Object **block_object
)
{
    if (block_object != NULL) {
        *block_object = NULL;
    }
    if (dwg == NULL || insert == NULL || insert->block_header == NULL) {
        return NULL;
    }

    Dwg_Object *object = insert->block_header->obj;
    if (object == NULL) {
        object = dwg_ref_object_silent(dwg, insert->block_header);
    }
    if (object == NULL || object->tio.object == NULL || object->tio.object->tio.BLOCK_HEADER == NULL) {
        return NULL;
    }
    if (!sitekeeper_object_matches(object, (int)DWG_TYPE_BLOCK_HEADER)) {
        return NULL;
    }

    if (block_object != NULL) {
        *block_object = object;
    }
    return object->tio.object->tio.BLOCK_HEADER;
}

static Dwg_Object_BLOCK_HEADER *sitekeeper_block_header_for_minsert(
    Dwg_Data *dwg,
    Dwg_Entity_MINSERT *insert,
    Dwg_Object **block_object
)
{
    if (block_object != NULL) {
        *block_object = NULL;
    }
    if (dwg == NULL || insert == NULL || insert->block_header == NULL) {
        return NULL;
    }

    Dwg_Object *object = insert->block_header->obj;
    if (object == NULL) {
        object = dwg_ref_object_silent(dwg, insert->block_header);
    }
    if (object == NULL || object->tio.object == NULL || object->tio.object->tio.BLOCK_HEADER == NULL) {
        return NULL;
    }
    if (!sitekeeper_object_matches(object, (int)DWG_TYPE_BLOCK_HEADER)) {
        return NULL;
    }

    if (block_object != NULL) {
        *block_object = object;
    }
    return object->tio.object->tio.BLOCK_HEADER;
}

static SiteKeeperLibreDWGTransform sitekeeper_insert_transform_values(
    BITCODE_3DPOINT ins_pt,
    BITCODE_3DPOINT scale,
    double rotation,
    Dwg_Object_BLOCK_HEADER *block_header
)
{
    const double sx = sitekeeper_insert_scale(scale.x);
    const double sy = sitekeeper_insert_scale(scale.y);
    const double resolved_rotation = isfinite(rotation) ? rotation : 0;
    const double cos_r = cos(resolved_rotation);
    const double sin_r = sin(resolved_rotation);
    const double base_x = block_header != NULL && isfinite(block_header->base_pt.x) ? block_header->base_pt.x : 0;
    const double base_y = block_header != NULL && isfinite(block_header->base_pt.y) ? block_header->base_pt.y : 0;
    const double insert_x = isfinite(ins_pt.x) ? ins_pt.x : 0;
    const double insert_y = isfinite(ins_pt.y) ? ins_pt.y : 0;

    SiteKeeperLibreDWGTransform transform;
    transform.m11 = sx * cos_r;
    transform.m12 = sx * sin_r;
    transform.m21 = -sy * sin_r;
    transform.m22 = sy * cos_r;
    transform.tx = insert_x - (transform.m11 * base_x + transform.m21 * base_y);
    transform.ty = insert_y - (transform.m12 * base_x + transform.m22 * base_y);
    transform.layoutSpace = 0;
    return transform;
}

static SiteKeeperLibreDWGTransform sitekeeper_insert_transform(
    Dwg_Entity_INSERT *insert,
    Dwg_Object_BLOCK_HEADER *block_header
)
{
    return sitekeeper_insert_transform_values(
        insert->ins_pt,
        insert->scale,
        insert->rotation,
        block_header
    );
}

static SiteKeeperLibreDWGTransform sitekeeper_minsert_transform(
    Dwg_Entity_MINSERT *insert,
    Dwg_Object_BLOCK_HEADER *block_header
)
{
    return sitekeeper_insert_transform_values(
        insert->ins_pt,
        insert->scale,
        insert->rotation,
        block_header
    );
}

static SiteKeeperLibreDWGTransform sitekeeper_insert_transform_with_array_offset(
    SiteKeeperLibreDWGTransform transform,
    int32_t column,
    int32_t row,
    double column_spacing,
    double row_spacing
)
{
    const double offset_x = (double)column * column_spacing;
    const double offset_y = (double)row * row_spacing;
    transform.tx += transform.m11 * offset_x + transform.m21 * offset_y;
    transform.ty += transform.m12 * offset_x + transform.m22 * offset_y;
    return transform;
}

static int sitekeeper_process_entity(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    SiteKeeperLibreDWGTransform transform,
    int depth
);

static void sitekeeper_process_insert_attributes(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Data *dwg,
    Dwg_Object_Ref **attribs,
    BITCODE_BL num_owned,
    SiteKeeperLibreDWGTransform parent_transform,
    int depth
)
{
    if (attribs == NULL || num_owned <= 0) {
        return;
    }
    for (BITCODE_BL index = 0; index < num_owned; index++) {
        Dwg_Object_Ref *attribute_ref = attribs[index];
        if (attribute_ref == NULL) {
            continue;
        }
        Dwg_Object *attribute_object = attribute_ref->obj;
        if (attribute_object == NULL) {
            attribute_object = dwg_ref_object_silent(dwg, attribute_ref);
        }
        if (attribute_object == NULL || attribute_object->tio.entity == NULL) {
            continue;
        }
        sitekeeper_process_entity(
            result,
            entity_count,
            entity_capacity,
            attribute_object->tio.entity,
            attribute_object,
            parent_transform,
            depth + 1
        );
    }
}

static int sitekeeper_expand_insert(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    SiteKeeperLibreDWGTransform parent_transform,
    int depth
)
{
    if (result == NULL || entity == NULL || object == NULL) {
        return 0;
    }
    if (depth >= SITEKEEPER_MAX_INSERT_DEPTH) {
        return 0;
    }

    Dwg_Object *block_object = NULL;
    SiteKeeperLibreDWGTransform base_insert_transform = sitekeeper_identity_transform();
    int32_t column_count = 1;
    int32_t row_count = 1;
    double column_spacing = 0;
    double row_spacing = 0;
    Dwg_Object_Ref **attribute_refs = NULL;
    BITCODE_BL attribute_count = 0;

    Dwg_Object_BLOCK_HEADER *block_header = NULL;
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_MINSERT) && entity->tio.MINSERT != NULL) {
        Dwg_Entity_MINSERT *minsert = entity->tio.MINSERT;
        block_header = sitekeeper_block_header_for_minsert(entity->dwg, minsert, &block_object);
        base_insert_transform = sitekeeper_minsert_transform(minsert, block_header);
        column_count = sitekeeper_insert_count(minsert->num_cols);
        row_count = sitekeeper_insert_count(minsert->num_rows);
        column_spacing = sitekeeper_insert_spacing(minsert->col_spacing);
        row_spacing = sitekeeper_insert_spacing(minsert->row_spacing);
        attribute_refs = minsert->attribs;
        attribute_count = minsert->num_owned;
    } else if (entity->tio.INSERT != NULL) {
        Dwg_Entity_INSERT *insert = entity->tio.INSERT;
        block_header = sitekeeper_block_header_for_insert(entity->dwg, insert, &block_object);
        base_insert_transform = sitekeeper_insert_transform(insert, block_header);
        column_count = sitekeeper_insert_count(insert->num_cols);
        row_count = sitekeeper_insert_count(insert->num_rows);
        column_spacing = sitekeeper_insert_spacing(insert->col_spacing);
        row_spacing = sitekeeper_insert_spacing(insert->row_spacing);
        attribute_refs = insert->attribs;
        attribute_count = insert->num_owned;
    } else {
        return 0;
    }

    if (block_header == NULL || block_object == NULL) {
        return 0;
    }

    const int32_t before_count = *entity_count;
    for (int32_t row = 0; row < row_count; row++) {
        for (int32_t column = 0; column < column_count; column++) {
            SiteKeeperLibreDWGTransform cell_transform = sitekeeper_insert_transform_with_array_offset(
                base_insert_transform,
                column,
                row,
                column_spacing,
                row_spacing
            );
            SiteKeeperLibreDWGTransform composed = sitekeeper_compose_transform(
                parent_transform,
                cell_transform
            );

            Dwg_Object *child = get_first_owned_entity(block_object);
            while (child != NULL) {
                if (child->tio.entity != NULL && sitekeeper_entity_is_visible(child->tio.entity)) {
                    sitekeeper_process_entity(
                        result,
                        entity_count,
                        entity_capacity,
                        child->tio.entity,
                        child,
                        composed,
                        depth + 1
                    );
                }
                child = get_next_owned_entity(block_object, child);
            }
        }
    }

    sitekeeper_process_insert_attributes(
        result,
        entity_count,
        entity_capacity,
        entity->dwg,
        attribute_refs,
        attribute_count,
        parent_transform,
        depth
    );

    const int32_t exported_count = *entity_count - before_count;
    if (exported_count > 0) {
        result->trace.exportedInsertEntityCount += exported_count;
    }
    return exported_count;
}

static int sitekeeper_process_entity(
    SiteKeeperLibreDWGEntityResult *result,
    int32_t *entity_count,
    int32_t *entity_capacity,
    Dwg_Object_Entity *entity,
    Dwg_Object *object,
    SiteKeeperLibreDWGTransform transform,
    int depth
)
{
    if (!sitekeeper_entity_is_visible(entity)) {
        return 0;
    }
    if (object == NULL) {
        object = sitekeeper_object_for_entity(entity);
    }

    if (sitekeeper_object_matches(object, (int)DWG_TYPE_LINE)
        || sitekeeper_object_matches(object, (int)DWG_TYPE_LINE_r11)) {
        result->trace.rawLineCount += 1;
        return sitekeeper_append_line(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_POINT)
        || sitekeeper_object_matches(object, (int)DWG_TYPE_POINT_r11)) {
        return sitekeeper_append_point(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_RAY)) {
        return sitekeeper_append_ray_or_xline(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            SiteKeeperLibreDWGEntityKindRay,
            &transform
        );
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_XLINE)) {
        return sitekeeper_append_ray_or_xline(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            SiteKeeperLibreDWGEntityKindXLine,
            &transform
        );
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_LWPOLYLINE)) {
        result->trace.rawPolylineCount += 1;
        return sitekeeper_append_lwpolyline(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_POLYLINE_2D)) {
        result->trace.rawPolylineCount += 1;
        return sitekeeper_append_polyline_2d(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_POLYLINE_3D)) {
        result->trace.rawPolylineCount += 1;
        return sitekeeper_append_polyline_3d(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_CIRCLE)) {
        result->trace.rawCircleCount += 1;
        return sitekeeper_append_circle(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_ARC)) {
        result->trace.rawArcCount += 1;
        return sitekeeper_append_arc(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_ELLIPSE)) {
        result->trace.rawEllipseCount += 1;
        return sitekeeper_append_ellipse(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_SPLINE)) {
        result->trace.rawSplineCount += 1;
        return sitekeeper_append_spline(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_SOLID)
        || sitekeeper_object_matches(object, (int)DWG_TYPE_SOLID_r11)) {
        result->trace.rawFilledShapeCount += 1;
        return sitekeeper_append_solid(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_TRACE)
        || sitekeeper_object_matches(object, (int)DWG_TYPE_TRACE_r11)) {
        result->trace.rawFilledShapeCount += 1;
        return sitekeeper_append_trace(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE__3DFACE)
        || sitekeeper_object_matches(object, (int)DWG_TYPE_3DFACE_r11)) {
        result->trace.rawFilledShapeCount += 1;
        return sitekeeper_append_3dface(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_LEADER)) {
        return sitekeeper_append_leader(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_MULTILEADER)) {
        result->trace.rawTextCount += 1;
        return sitekeeper_append_multileader(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_MLINE)) {
        return sitekeeper_append_mline(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_TEXT)) {
        result->trace.rawTextCount += 1;
        return sitekeeper_append_text(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_MTEXT)) {
        result->trace.rawTextCount += 1;
        return sitekeeper_append_mtext(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_ATTRIB)) {
        result->trace.rawTextCount += 1;
        return sitekeeper_append_attrib(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_ATTDEF)) {
        result->trace.rawTextCount += 1;
        return sitekeeper_append_attdef(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DIMENSION_LINEAR)) {
        result->trace.rawDimensionCount += 1;
        return sitekeeper_append_dimension_linear(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DIMENSION_ALIGNED)) {
        result->trace.rawDimensionCount += 1;
        return sitekeeper_append_dimension_aligned(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DIMENSION_RADIUS)) {
        result->trace.rawDimensionCount += 1;
        return sitekeeper_append_dimension_radius(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DIMENSION_DIAMETER)) {
        result->trace.rawDimensionCount += 1;
        return sitekeeper_append_dimension_diameter(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DIMENSION_ORDINATE)) {
        result->trace.rawDimensionCount += 1;
        return sitekeeper_append_dimension_ordinate(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DIMENSION_ANG3PT)) {
        result->trace.rawDimensionCount += 1;
        return sitekeeper_append_dimension_ang3pt(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DIMENSION_ANG2LN)) {
        result->trace.rawDimensionCount += 1;
        return sitekeeper_append_dimension_ang2ln(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_TABLE)) {
        result->trace.rawTextCount += 1;
        return sitekeeper_append_table(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_HATCH)) {
        result->trace.rawHatchCount += 1;
        return sitekeeper_append_hatch(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_IMAGE)) {
        return sitekeeper_append_image(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_WIPEOUT)) {
        return sitekeeper_append_wipeout(result, entity_count, entity_capacity, entity, object, &transform);
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_PDFUNDERLAY)) {
        return sitekeeper_append_underlay(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            entity->tio.PDFUNDERLAY,
            &transform
        );
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DWFUNDERLAY)) {
        return sitekeeper_append_underlay(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            entity->tio.DWFUNDERLAY,
            &transform
        );
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_DGNUNDERLAY)) {
        return sitekeeper_append_underlay(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            entity->tio.DGNUNDERLAY,
            &transform
        );
    }
    if (sitekeeper_is_insert_object(object)) {
        result->trace.rawInsertCount += 1;
        return sitekeeper_expand_insert(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            transform,
            depth
        );
    }
    if (sitekeeper_object_matches(object, (int)DWG_TYPE_PROXY_ENTITY)) {
        const int is_tianzheng = sitekeeper_object_is_tianzheng(object);
        result->trace.rawProxyEntityCount += 1;
        if (is_tianzheng) {
            result->trace.rawTianzhengProxyCount += 1;
        }
        return sitekeeper_append_proxy_entity(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            is_tianzheng
                ? SiteKeeperLibreDWGEntityKindTianzhengProxy
                : SiteKeeperLibreDWGEntityKindProxy,
            &transform
        );
    }
    if (sitekeeper_object_is_tianzheng(object)) {
        result->trace.rawProxyEntityCount += 1;
        result->trace.rawTianzhengProxyCount += 1;
        return sitekeeper_append_proxy_entity(
            result,
            entity_count,
            entity_capacity,
            entity,
            object,
            SiteKeeperLibreDWGEntityKindTianzhengProxy,
            &transform
        );
    }
    return 0;
}

int32_t SiteKeeperLibreDWGReadBasic2D(const char *path, SiteKeeperLibreDWGEntityResult *result)
{
    if (result == NULL) {
        return -1;
    }
    sitekeeper_reset_result(result);

    if (path == NULL || path[0] == '\0') {
        return -2;
    }

    Dwg_Data dwg;
    memset(&dwg, 0, sizeof(dwg));

    const int read_error = dwg_read_file(path, &dwg);
    result->trace.readError = (int32_t)read_error;
    result->trace.rawEntityCount = (int32_t)dwg_get_num_entities(&dwg);

    if (read_error >= DWG_ERR_CRITICAL || result->trace.rawEntityCount <= 0) {
        dwg_free(&dwg);
        return read_error;
    }

    Dwg_Object_Entity **entities = dwg_get_entities(&dwg);
    if (entities == NULL) {
        dwg_free(&dwg);
        return read_error;
    }

    int32_t entity_capacity = result->trace.rawEntityCount > 32 ? result->trace.rawEntityCount : 32;
    result->entities = (SiteKeeperLibreDWGEntity *)calloc(
        (size_t)entity_capacity,
        sizeof(SiteKeeperLibreDWGEntity)
    );
    if (result->entities == NULL) {
        free(entities);
        dwg_free(&dwg);
        return -3;
    }

    int32_t entity_count = 0;
    const SiteKeeperLibreDWGTransform identity = sitekeeper_identity_transform();
    for (int32_t index = 0; index < result->trace.rawEntityCount; index++) {
        Dwg_Object_Entity *entity = entities[index];
        if (!sitekeeper_entity_is_visible(entity) || !sitekeeper_is_top_level_entity(entity)) {
            continue;
        }

        Dwg_Object *object = sitekeeper_object_for_entity(entity);
        SiteKeeperLibreDWGTransform entity_transform = identity;
        entity_transform.layoutSpace = sitekeeper_entity_layout_space(entity);
        sitekeeper_process_entity(result, &entity_count, &entity_capacity, entity, object, entity_transform, 0);
    }
    free(entities);

    result->entityCount = entity_count;

    if (entity_count == 0) {
        result->trace.minX = 0;
        result->trace.minY = 0;
        result->trace.maxX = 0;
        result->trace.maxY = 0;
    }

    dwg_free(&dwg);
    return read_error;
}

void SiteKeeperLibreDWGFreeBasic2D(SiteKeeperLibreDWGEntityResult *result)
{
    if (result == NULL || result->entities == NULL) {
        return;
    }

    for (int32_t index = 0; index < result->entityCount; index++) {
        free(result->entities[index].points);
        free(result->entities[index].layerName);
        free(result->entities[index].sourceHandle);
        free(result->entities[index].rawText);
        free(result->entities[index].textStyleName);
        free(result->entities[index].fontName);
        free(result->entities[index].bigFontName);
        free(result->entities[index].objectName);
        free(result->entities[index].unsupportedReason);
    }
    free(result->entities);
    result->entities = NULL;
    result->entityCount = 0;
}
