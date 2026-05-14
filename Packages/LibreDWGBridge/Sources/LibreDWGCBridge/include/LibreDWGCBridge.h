#ifndef LIBREDWGC_BRIDGE_H
#define LIBREDWGC_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum SKCADPrimitiveKind {
    SKCADPrimitiveLine = 0,
    SKCADPrimitivePolyline = 1,
    SKCADPrimitiveArc = 2,
    SKCADPrimitiveCircle = 3,
    SKCADPrimitiveEllipse = 4,
    SKCADPrimitiveText = 5,
    SKCADPrimitiveMText = 6,
    SKCADPrimitiveDimension = 7,
    SKCADPrimitiveHatch = 8,
    SKCADPrimitiveLeader = 9,
    SKCADPrimitiveImage = 10,
    SKCADPrimitiveWipeout = 11,
    SKCADPrimitiveBlockRef = 12,
    SKCADPrimitiveUnknownProxy = 13
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
    SKCADPoint *points;
    int pointCount;
    char *layerName;
    unsigned int strokeRGB;
    double strokeWidth;
    double radius;
    double startAngle;
    double endAngle;
    double textHeight;
    double textRotation;
    char *text;
    char *rawTextBytesHex;
    char *textStyleName;
    char *fontFile;
    char *bigFontFile;
    int chosenCodepage;
} SKCADPrimitive;

typedef struct SKCADParseResult {
    SKCADPrimitive *primitives;
    int primitiveCount;
    int totalObjectCount;
    int unsupportedEntityCount;
    int requestedCodepage;
    int readStatus;
    int dwgVersion;
    int dwgFromVersion;
    int dwgHeaderDwgVersion;
    int dwgHeaderMaintVersion;
    int headerCodepage;
    int effectiveCodepage;
    int primitiveLimit;
    int objectLimit;
    unsigned long long primitiveMemoryBudget;
    unsigned long long estimatedPrimitiveMemory;
    int textPrimitiveCount;
    int suspiciousTextCount;
    int mojibakeTextCount;
    char dwgVersionCode[16];
    char dwgVersionType[32];
    char dwgVersionDescription[96];
    char styleTableSummary[512];
    char unsupportedEntitySummary[256];
    char errorMessage[512];
} SKCADParseResult;

int sk_libredwg_parse_file(const char *path, SKCADParseResult *result);
int sk_libredwg_parse_file_with_codepage(const char *path, int codepage_override, SKCADParseResult *result);
void sk_libredwg_free_parse_result(SKCADParseResult *result);

#ifdef __cplusplus
}
#endif

#endif
