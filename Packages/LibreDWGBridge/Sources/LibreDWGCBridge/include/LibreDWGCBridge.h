#ifndef LIBREDWGC_BRIDGE_H
#define LIBREDWGC_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum SKCADPrimitiveKind {
    SKCADPrimitiveLine = 0,
    SKCADPrimitiveArc = 1,
    SKCADPrimitiveCircle = 2,
    SKCADPrimitiveText = 3
} SKCADPrimitiveKind;

typedef struct SKCADPoint {
    double x;
    double y;
} SKCADPoint;

typedef struct SKCADPrimitive {
    SKCADPrimitiveKind kind;
    SKCADPoint start;
    SKCADPoint end;
    SKCADPoint center;
    char *layerName;
    unsigned int strokeRGB;
    double strokeWidth;
    double radius;
    double startAngle;
    double endAngle;
    double textHeight;
    double textRotation;
    char *text;
} SKCADPrimitive;

typedef struct SKCADParseResult {
    SKCADPrimitive *primitives;
    int primitiveCount;
    int totalObjectCount;
    int unsupportedEntityCount;
    char errorMessage[512];
} SKCADParseResult;

int sk_libredwg_parse_file(const char *path, SKCADParseResult *result);
int sk_libredwg_parse_file_with_codepage(const char *path, int codepage_override, SKCADParseResult *result);
void sk_libredwg_free_parse_result(SKCADParseResult *result);

#ifdef __cplusplus
}
#endif

#endif
