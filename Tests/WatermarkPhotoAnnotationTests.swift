import Foundation
import UIKit
import Testing
@testable import sitekeeper

struct WatermarkPhotoAnnotationTests {
    @Test func annotationsClampNormalizedPositionsAndKeepSizeWhenMoved() {
        let mark = WatermarkPhotoAnnotation(kind: .arrow, start: CGPoint(x: -1, y: 0.2), end: CGPoint(x: 0.4, y: 2))
        #expect(mark.start == CGPoint(x: 0, y: 0.2))
        #expect(mark.end == CGPoint(x: 0.4, y: 1))
        let moved = mark.movingCenter(to: CGPoint(x: 1, y: 0))
        #expect(abs(moved.end.x - moved.start.x - 0.4) < 0.0001)
        #expect(abs(moved.end.y - moved.start.y - 0.8) < 0.0001)
        #expect(moved.start.x >= 0 && moved.end.x <= 1)
        #expect(moved.start.y >= 0 && moved.end.y <= 1)
        let invalid = WatermarkPhotoAnnotation(kind: .circle, start: CGPoint(x: CGFloat.nan, y: .infinity), end: .zero)
        #expect(invalid.start == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func renderingProducesSeparateCopyAtOriginalPixelDimensions() async throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let original = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320), format: format).image { _ in
            UIColor.blue.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 240, height: 320)).fill()
        }
        let originalData = try #require(original.pngData())
        let annotations = [
            WatermarkPhotoAnnotation(kind: .arrow, start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.7, y: 0.5)),
            WatermarkPhotoAnnotation(kind: .circle, start: CGPoint(x: 0.3, y: 0.3), end: CGPoint(x: 0.8, y: 0.6)),
            WatermarkPhotoAnnotation(kind: .text, start: CGPoint(x: 0.1, y: 0.7), end: CGPoint(x: 0.1, y: 0.7), text: "整改位置")
        ]
        let marked = await Task.detached {
            WatermarkPhotoAnnotationRenderer.render(image: original, annotations: annotations)
        }.value
        #expect(marked.size == original.size)
        #expect(marked.scale == original.scale)
        #expect(marked.cgImage?.width == 480)
        #expect(marked.cgImage?.height == 640)
        #expect(marked.pngData() != originalData)
        #expect(original.pngData() == originalData)
    }

    @Test func annotationKindsEachProduceVisibleMark() throws {
        let base = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { _ in
            UIColor.blue.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 300, height: 400)).fill()
        }
        let unmarked = WatermarkPhotoAnnotationRenderer.render(image: base, annotations: []).pngData()
        for kind in WatermarkPhotoAnnotation.Kind.allCases {
            let mark = WatermarkPhotoAnnotation(kind: kind, start: CGPoint(x: 0.2, y: 0.2),
                                               end: CGPoint(x: 0.7, y: 0.5), text: "现场问题")
            let marked = WatermarkPhotoAnnotationRenderer.render(image: base, annotations: [mark])
            #expect(marked.pngData() != unmarked)
        }
    }
}
