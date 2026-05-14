#include "LibreDWGCBridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEXT_SAMPLE_LIMIT 80

static void print_json_string(const char *text) {
  putchar('"');
  if (text) {
    const unsigned char *cursor = (const unsigned char *)text;
    while (*cursor) {
      switch (*cursor) {
      case '"':
        fputs("\\\"", stdout);
        break;
      case '\\':
        fputs("\\\\", stdout);
        break;
      case '\b':
        fputs("\\b", stdout);
        break;
      case '\f':
        fputs("\\f", stdout);
        break;
      case '\n':
        fputs("\\n", stdout);
        break;
      case '\r':
        fputs("\\r", stdout);
        break;
      case '\t':
        fputs("\\t", stdout);
        break;
      default:
        if (*cursor < 0x20) {
          printf("\\u%04x", *cursor);
        } else {
          putchar(*cursor);
        }
        break;
      }
      cursor += 1;
    }
  }
  putchar('"');
}

static void print_json_key_string(const char *key, const char *value,
                                  int trailing_comma) {
  printf("  \"%s\": ", key);
  print_json_string(value);
  printf("%s\n", trailing_comma ? "," : "");
}

static void print_json_key_int(const char *key, int value, int trailing_comma) {
  printf("  \"%s\": %d%s\n", key, value, trailing_comma ? "," : "");
}

static void print_json_key_uint64(const char *key, unsigned long long value,
                                  int trailing_comma) {
  printf("  \"%s\": %llu%s\n", key, value, trailing_comma ? "," : "");
}

static const char *primitive_kind_name(SKCADPrimitiveKind kind) {
  switch (kind) {
  case SKCADPrimitiveText:
    return "TEXT";
  case SKCADPrimitiveMText:
    return "MTEXT";
  case SKCADPrimitiveDimension:
    return "DIMENSION";
  default:
    return "OTHER";
  }
}

static int is_text_primitive(const SKCADPrimitive *primitive) {
  if (!primitive) {
    return 0;
  }
  return primitive->kind == SKCADPrimitiveText ||
         primitive->kind == SKCADPrimitiveMText ||
         primitive->kind == SKCADPrimitiveDimension;
}

static int text_contains(const char *text, const char *needle) {
  return text && needle && strstr(text, needle) != NULL;
}

static int text_has_non_ascii(const char *text) {
  if (!text) {
    return 0;
  }
  const unsigned char *cursor = (const unsigned char *)text;
  while (*cursor) {
    if (*cursor >= 0x80) {
      return 1;
    }
    cursor++;
  }
  return 0;
}

static int is_interesting_text_sample(const SKCADPrimitive *primitive) {
  if (!primitive || !primitive->text) {
    return 0;
  }
  return text_contains(primitive->text, "%%") ||
         text_contains(primitive->text, "\\U+") ||
         text_contains(primitive->text, "\\M+") ||
         text_contains(primitive->text, "??") ||
         text_contains(primitive->text, "\xEF\xBF\xBD") ||
         (text_has_non_ascii(primitive->text) &&
          ((primitive->bigFontFile && primitive->bigFontFile[0]) ||
           (primitive->fontFile && strstr(primitive->fontFile, ".shx"))));
}

static void print_text_sample(const SKCADPrimitive *primitive) {
  printf("    {");
  printf("\"kind\": ");
  print_json_string(primitive_kind_name(primitive->kind));
  printf(", \"layerName\": ");
  print_json_string(primitive->layerName);
  printf(", \"text\": ");
  print_json_string(primitive->text);
  printf(", \"rawTextBytesHex\": ");
  print_json_string(primitive->rawTextBytesHex);
  printf(", \"textStyleName\": ");
  print_json_string(primitive->textStyleName);
  printf(", \"fontFile\": ");
  print_json_string(primitive->fontFile);
  printf(", \"bigFontFile\": ");
  print_json_string(primitive->bigFontFile);
  printf(", \"chosenCodepage\": %d", primitive->chosenCodepage);
  printf(", \"x\": %.6f", primitive->start.x);
  printf(", \"y\": %.6f", primitive->start.y);
  printf(", \"textHeight\": %.6f", primitive->textHeight);
  printf(", \"textRotation\": %.6f", primitive->textRotation);
  printf("}");
}

static int text_sample_already_selected(const int *indices, int count, int value) {
  for (int index = 0; index < count; index++) {
    if (indices[index] == value) {
      return 1;
    }
  }
  return 0;
}

static void print_text_samples(const SKCADParseResult *result) {
  int selected[TEXT_SAMPLE_LIMIT];
  int selected_count = 0;

  printf("  \"textSamples\": [\n");
  if (result && result->primitives && result->primitiveCount > 0) {
    for (int index = 0;
         index < result->primitiveCount && selected_count < TEXT_SAMPLE_LIMIT;
         index++) {
      const SKCADPrimitive *primitive = &result->primitives[index];
      if (is_text_primitive(primitive) && is_interesting_text_sample(primitive)) {
        selected[selected_count++] = index;
      }
    }
    for (int index = 0;
         index < result->primitiveCount && selected_count < TEXT_SAMPLE_LIMIT;
         index++) {
      const SKCADPrimitive *primitive = &result->primitives[index];
      if (!is_text_primitive(primitive) ||
          text_sample_already_selected(selected, selected_count, index)) {
        continue;
      }
      selected[selected_count++] = index;
    }
    for (int index = 0; index < selected_count; index++) {
      print_text_sample(&result->primitives[selected[index]]);
      printf("%s\n", index + 1 < selected_count ? "," : "");
    }
  }
  printf("  ]\n");
}

static void print_xrefs(const SKCADParseResult *result, int trailing_comma) {
  printf("  \"xrefs\": [\n");
  if (result && result->xrefs && result->xrefReferenceCount > 0) {
    for (int index = 0; index < result->xrefReferenceCount; index++) {
      const SKCADXrefReference *xref = &result->xrefs[index];
      printf("    {");
      printf("\"name\": ");
      print_json_string(xref->name);
      printf(", \"savedPath\": ");
      print_json_string(xref->savedPath);
      printf(", \"isOverlay\": %s", xref->isOverlay ? "true" : "false");
      printf(", \"isLoaded\": %s", xref->isLoaded ? "true" : "false");
      printf(", \"isResolvedInDWG\": %s",
             xref->isResolvedInDWG ? "true" : "false");
      printf(", \"referenceCount\": %d", xref->referenceCount);
      printf("}%s\n", index + 1 < result->xrefReferenceCount ? "," : "");
    }
  }
  printf("  ]%s\n", trailing_comma ? "," : "");
}

static void print_usage(const char *program) {
  fprintf(stderr, "usage: %s [--geometry-only] [--codepage N] FILE.dwg\n",
          program);
}

int main(int argc, char **argv) {
  int parse_options = 0;
  int codepage = 0;
  const char *path = NULL;

  for (int index = 1; index < argc; index++) {
    if (strcmp(argv[index], "--geometry-only") == 0) {
      parse_options |= SKCADParseOptionSkipText;
      continue;
    }
    if (strcmp(argv[index], "--codepage") == 0) {
      if (index + 1 >= argc) {
        print_usage(argv[0]);
        return 2;
      }
      codepage = atoi(argv[++index]);
      continue;
    }
    if (argv[index][0] == '-') {
      print_usage(argv[0]);
      return 2;
    }
    path = argv[index];
  }

  if (!path || !path[0]) {
    print_usage(argv[0]);
    return 2;
  }

  SKCADParseResult result;
  memset(&result, 0, sizeof(result));
  const int ok =
      sk_libredwg_parse_file_with_options(path, codepage, parse_options, &result);

  printf("{\n");
  printf("  \"ok\": %s,\n", ok ? "true" : "false");
  print_json_key_int("primitiveCount", result.primitiveCount, 1);
  print_json_key_int("totalObjectCount", result.totalObjectCount, 1);
  print_json_key_int("unsupportedEntityCount", result.unsupportedEntityCount, 1);
  print_json_key_int("requestedCodepage", result.requestedCodepage, 1);
  print_json_key_int("readStatus", result.readStatus, 1);
  print_json_key_int("dwgVersion", result.dwgVersion, 1);
  print_json_key_int("dwgFromVersion", result.dwgFromVersion, 1);
  print_json_key_int("headerCodepage", result.headerCodepage, 1);
  print_json_key_int("effectiveCodepage", result.effectiveCodepage, 1);
  print_json_key_int("primitiveLimit", result.primitiveLimit, 1);
  print_json_key_int("objectLimit", result.objectLimit, 1);
  print_json_key_uint64("primitiveMemoryBudget", result.primitiveMemoryBudget, 1);
  print_json_key_uint64("estimatedPrimitiveMemory",
                        result.estimatedPrimitiveMemory, 1);
  print_json_key_int("textPrimitiveCount", result.textPrimitiveCount, 1);
  print_json_key_int("suspiciousTextCount", result.suspiciousTextCount, 1);
  print_json_key_int("mojibakeTextCount", result.mojibakeTextCount, 1);
  print_json_key_int("blockInsertCount", result.blockInsertCount, 1);
  print_json_key_int("blockMInsertCount", result.blockMInsertCount, 1);
  print_json_key_int("blockExpandedCount", result.blockExpandedCount, 1);
  print_json_key_int("blockUnresolvedCount", result.blockUnresolvedCount, 1);
  print_json_key_int("blockRecursiveSkipCount", result.blockRecursiveSkipCount, 1);
  print_json_key_int("blockDepthSkipCount", result.blockDepthSkipCount, 1);
  print_json_key_int("blockXrefCount", result.blockXrefCount, 1);
  print_json_key_int("blockAnonymousCount", result.blockAnonymousCount, 1);
  print_json_key_int("blockAttributeCount", result.blockAttributeCount, 1);
  print_json_key_int("blockAttdefCount", result.blockAttdefCount, 1);
  print_json_key_int("blockDynamicProxyCount", result.blockDynamicProxyCount, 1);
  print_json_key_int("proxyObjectCount", result.proxyObjectCount, 1);
  print_json_key_int("xrefReferenceCount", result.xrefReferenceCount, 1);
  print_json_key_string("dwgVersionCode", result.dwgVersionCode, 1);
  print_json_key_string("dwgVersionType", result.dwgVersionType, 1);
  print_json_key_string("dwgVersionDescription", result.dwgVersionDescription, 1);
  print_json_key_string("styleTableSummary", result.styleTableSummary, 1);
  print_json_key_string("unsupportedEntitySummary",
                        result.unsupportedEntitySummary, 1);
  print_json_key_string("blockReferenceSummary", result.blockReferenceSummary, 1);
  print_json_key_string("xrefReferenceSummary", result.xrefReferenceSummary, 1);
  print_json_key_string("errorMessage", result.errorMessage, 1);
  print_xrefs(&result, 1);
  print_text_samples(&result);
  printf("}\n");

  sk_libredwg_free_parse_result(&result);
  return ok ? 0 : 1;
}
