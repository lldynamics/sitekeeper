import Foundation
import UIKit
import Testing
@testable import sitekeeper

struct WatermarkCameraCaptureTests {
    @Test func manualLocationNeverClaimsDeviceFreshness() {
        let snapshot = WatermarkLocationSnapshot.manual(text: "三号楼东侧")
        #expect(snapshot.freshness() == .manual)
        #expect(snapshot.timestamp == nil)
        #expect(snapshot.horizontalAccuracy == nil)
    }

    @Test func deviceLocationPreservesAgeAndRejectsInvalidAccuracy() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = WatermarkLocationSnapshot(text: "现场", timestamp: now.addingTimeInterval(-30), horizontalAccuracy: 25, provenance: .device)
        #expect(fresh.freshness(at: now) == .fresh)
        #expect(fresh.freshness(at: now.addingTimeInterval(100)) == .stale)
        let invalid = WatermarkLocationSnapshot(text: "旧坐标", timestamp: now, horizontalAccuracy: -1, provenance: .device)
        #expect(invalid.freshness(at: now) == .invalid)
        let future = WatermarkLocationSnapshot(text: "时钟异常", timestamp: now.addingTimeInterval(60), horizontalAccuracy: 10, provenance: .device)
        #expect(future.freshness(at: now) == .invalid)
    }

    @Test func savedDeviceLocationDoesNotBecomeNewWhenDecoded() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fix = WatermarkLocationSnapshot(text: "现场地址", timestamp: now.addingTimeInterval(-3600), horizontalAccuracy: 150, provenance: .device)
        let decoded = try JSONDecoder().decode(WatermarkLocationSnapshot.self, from: JSONEncoder().encode(fix))
        #expect(decoded == fix)
        #expect(decoded.freshness(at: now) == .stale)
        let timestamp = try #require(decoded.timestamp)
        #expect(decoded.statusText(at: now) == String(format: AppLocalization.string("历史定位（%@），请核对"), Formatters.dateTime.string(from: timestamp)))
    }

    @Test func missingAndNonfiniteDeviceMetadataIsInvalid() {
        let now = Date()
        for accuracy: Double? in [nil, .nan, .infinity] {
            let fix = WatermarkLocationSnapshot(text: "现场", timestamp: now, horizontalAccuracy: accuracy, provenance: .device)
            #expect(fix.freshness(at: now) == .invalid)
        }
        #expect(WatermarkLocationSnapshot(text: "现场", timestamp: nil, horizontalAccuracy: 5, provenance: .device).freshness() == .invalid)
    }

    @Test func photoFramingFitsWithoutCroppingInBothOrientations() {
        for landscape in [false, true] {
            let available = CGSize(width: 700, height: 450)
            let size = WatermarkCameraFraming.fittedSize(in: available, landscape: landscape)
            #expect(size.width <= available.width)
            #expect(size.height <= available.height)
            #expect(abs(size.width / size.height - (landscape ? 4.0 / 3.0 : 3.0 / 4.0)) < 0.0001)
        }
        #expect(WatermarkCameraFraming.rotationAngle(for: .portrait) == 90)
        #expect(WatermarkCameraFraming.rotationAngle(for: .landscapeRight) == 0)
        #expect(WatermarkCameraFraming.rotationAngle(for: .landscapeLeft) == 180)
    }

    @Test func cancellationInvalidatesCallbacksAndReplacementBurst() {
        var gate = WatermarkCameraCaptureGenerationGate()
        let old = gate.begin()
        gate.invalidate()
        #expect(!gate.accepts(old))
        let replacement = gate.begin()
        #expect(!gate.accepts(old))
        #expect(gate.accepts(replacement))
    }
}

struct WatermarkRectificationEligibilityTests {
    @Test func frozenProjectAndExistingEvidenceAreRequiredBoundaries() {
        let project = UUID()
        let eligible = SiteTodo(title: "立柱固定", rectificationBeforePhotoFileName: "before.jpg", projectId: project)
        #expect(WatermarkRectificationEligibility.accepts(eligible, projectID: project))
        #expect(!WatermarkRectificationEligibility.accepts(eligible, projectID: UUID()))
        let existingEvidence = SiteTodo(title: "已整改", rectificationAfterPhotoFileName: "after.jpg", projectId: project)
        #expect(!WatermarkRectificationEligibility.accepts(existingEvidence, projectID: project))
        let unassigned = SiteTodo(title: "未归属")
        #expect(WatermarkRectificationEligibility.accepts(unassigned, projectID: nil))
        #expect(!WatermarkRectificationEligibility.accepts(unassigned, projectID: project))
    }
}
