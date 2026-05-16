#ifndef SITEKEEPER_LIBREDWG_SHIM_H
#define SITEKEEPER_LIBREDWG_SHIM_H

#include <stdint.h>

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
    SiteKeeperLibreDWGEntityKindUnderlay = 21
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
    char *layerName;
    char *sourceHandle;
    char *rawText;
    char *textStyleName;
    char *fontName;
    char *bigFontName;
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
} SiteKeeperLibreDWGEntity;

typedef struct SiteKeeperLibreDWGTrace {
    int32_t readError;
    int32_t rawEntityCount;
    int32_t rawLineCount;
    int32_t rawPolylineCount;
    int32_t rawCircleCount;
    int32_t rawArcCount;
    int32_t rawInsertCount;
    int32_t rawTextCount;
    int32_t rawDimensionCount;
    int32_t rawHatchCount;
    int32_t rawEllipseCount;
    int32_t rawSplineCount;
    int32_t rawFilledShapeCount;
    int32_t exportedLineCount;
    int32_t exportedPolylineCount;
    int32_t exportedCircleCount;
    int32_t exportedArcCount;
    int32_t exportedInsertEntityCount;
    int32_t exportedTextCount;
    int32_t exportedDimensionCount;
    int32_t exportedHatchCount;
    int32_t exportedEllipseCount;
    int32_t exportedSplineCount;
    int32_t exportedFilledShapeCount;
    double minX;
    double minY;
    double maxX;
    double maxY;
} SiteKeeperLibreDWGTrace;

typedef struct SiteKeeperLibreDWGEntityResult {
    SiteKeeperLibreDWGEntity *entities;
    int32_t entityCount;
    SiteKeeperLibreDWGTrace trace;
} SiteKeeperLibreDWGEntityResult;

int32_t SiteKeeperLibreDWGReadBasic2D(const char *path, SiteKeeperLibreDWGEntityResult *result);
void SiteKeeperLibreDWGFreeBasic2D(SiteKeeperLibreDWGEntityResult *result);

#ifdef __cplusplus
}
#endif

#endif
