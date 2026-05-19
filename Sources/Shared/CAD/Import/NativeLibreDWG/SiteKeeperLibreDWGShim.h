#ifndef SITEKEEPER_LIBREDWG_SHIM_H
#define SITEKEEPER_LIBREDWG_SHIM_H

#include <stdint.h>

#define SITEKEEPER_LIBREDWG_MAX_ENTITY_COUNT 500000
#define SITEKEEPER_LIBREDWG_STATUS_ENTITY_LIMIT_EXCEEDED -4

#ifdef __cplusplus
extern "C" {
#endif

typedef enum SiteKeeperLibreDWGEntityKind {
    SiteKeeperLibreDWGEntityKindLine = 1,
    SiteKeeperLibreDWGEntityKindPolyline = 2,
    SiteKeeperLibreDWGEntityKindLWPolyline = 3,
    SiteKeeperLibreDWGEntityKindCircle = 4,
    SiteKeeperLibreDWGEntityKindArc = 5,
    SiteKeeperLibreDWGEntityKindText = 6,
    SiteKeeperLibreDWGEntityKindMText = 7,
    SiteKeeperLibreDWGEntityKindAttrib = 8,
    SiteKeeperLibreDWGEntityKindDimension = 9,
    SiteKeeperLibreDWGEntityKindHatch = 10,
    SiteKeeperLibreDWGEntityKindEllipse = 11,
    SiteKeeperLibreDWGEntityKindSpline = 12,
    SiteKeeperLibreDWGEntityKindFilledShape = 13,
    SiteKeeperLibreDWGEntityKindPoint = 14,
    SiteKeeperLibreDWGEntityKindRay = 15,
    SiteKeeperLibreDWGEntityKindXLine = 16,
    SiteKeeperLibreDWGEntityKindLeader = 17,
    SiteKeeperLibreDWGEntityKindMLine = 18,
    SiteKeeperLibreDWGEntityKindImage = 19,
    SiteKeeperLibreDWGEntityKindWipeout = 20,
    SiteKeeperLibreDWGEntityKindUnderlay = 21,
    SiteKeeperLibreDWGEntityKindProxy = 22,
    SiteKeeperLibreDWGEntityKindTianzhengProxy = 23
} SiteKeeperLibreDWGEntityKind;

typedef struct SiteKeeperLibreDWGPoint {
    double x;
    double y;
} SiteKeeperLibreDWGPoint;

typedef struct SiteKeeperLibreDWGEntity {
    int32_t kind;
    SiteKeeperLibreDWGPoint *points;
    int32_t pointCount;
    int32_t isClosed;
    int32_t layoutSpace;
    char *layerName;
    char *sourceHandle;
    char *rawText;
    char *rawTextBytesHex;
    int32_t rawTextIsUTF8;
    char *textStyleName;
    char *fontName;
    char *bigFontName;
    char *objectName;
    char *unsupportedReason;
    uint32_t colorARGB;
    double lineWeight;
    double textX;
    double textY;
    double textHeight;
    double textRotation;
    double textWidthFactor;
    double textBoxWidth;
    double textBoxHeight;
    int32_t textHorizontalAlignment;
    int32_t textVerticalAlignment;
    int32_t hatchFillMode;
} SiteKeeperLibreDWGEntity;

typedef struct SiteKeeperLibreDWGViewport {
    char *sourceHandle;
    int32_t layoutSpace;
    int32_t onOff;
    int32_t viewportID;
    double centerX;
    double centerY;
    double width;
    double height;
    double viewCenterX;
    double viewCenterY;
    double viewHeight;
    double twistRadians;
} SiteKeeperLibreDWGViewport;

typedef struct SiteKeeperLibreDWGTrace {
    int32_t readError;
    int32_t rawEntityCount;
    int32_t rawLineCount;
    int32_t rawPolylineCount;
    int32_t rawCircleCount;
    int32_t rawArcCount;
    int32_t rawInsertCount;
    int32_t rawTextCount;
    int32_t rawTextEntityCount;
    int32_t rawMTextEntityCount;
    int32_t rawAttribEntityCount;
    int32_t rawAttdefEntityCount;
    int32_t rawDimensionCount;
    int32_t rawHatchCount;
    int32_t rawEllipseCount;
    int32_t rawSplineCount;
    int32_t rawFilledShapeCount;
    int32_t rawProxyEntityCount;
    int32_t rawTianzhengProxyCount;
    int32_t rawMLeaderCount;
    int32_t rawViewportCount;
    int32_t mleaderTextCandidateCount;
    int32_t proxyTextCandidateCount;
    int32_t tianzhengTextCandidateCount;
    int32_t exportedLineCount;
    int32_t exportedPolylineCount;
    int32_t exportedCircleCount;
    int32_t exportedArcCount;
    int32_t exportedInsertEntityCount;
    int32_t exportedTextCount;
    int32_t exportedTextEntityCount;
    int32_t exportedMTextEntityCount;
    int32_t exportedAttribEntityCount;
    int32_t exportedMLeaderTextCount;
    int32_t exportedDimensionCount;
    int32_t exportedHatchCount;
    int32_t exportedEllipseCount;
    int32_t exportedSplineCount;
    int32_t exportedFilledShapeCount;
    int32_t exportedProxyEntityCount;
    int32_t exportedTianzhengProxyCount;
    int32_t exportedViewportCount;
    int32_t skippedViewportCount;
    int32_t preferredTextCodePage;
    int32_t libredwgTextCodePage;
    int32_t nativeTextDecodeEnabled;
    double minX;
    double minY;
    double maxX;
    double maxY;
} SiteKeeperLibreDWGTrace;

typedef struct SiteKeeperLibreDWGEntityResult {
    SiteKeeperLibreDWGEntity *entities;
    int32_t entityCount;
    SiteKeeperLibreDWGViewport *viewports;
    int32_t viewportCount;
    SiteKeeperLibreDWGTrace trace;
} SiteKeeperLibreDWGEntityResult;

int32_t SiteKeeperLibreDWGReadBasic2D(const char *path, SiteKeeperLibreDWGEntityResult *result);
int32_t SiteKeeperLibreDWGReadBasic2DWithTextCodePage(
    const char *path,
    int32_t preferredTextCodePage,
    SiteKeeperLibreDWGEntityResult *result
);
void SiteKeeperLibreDWGFreeBasic2D(SiteKeeperLibreDWGEntityResult *result);

#ifdef __cplusplus
}
#endif

#endif
