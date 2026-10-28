import Foundation
import Combine
import CoreLocation

/// Device timestamps and accuracy survive geocoding, so cached coordinates never become a new fix.
struct WatermarkLocationSnapshot: Codable, Equatable, Sendable {
    enum Provenance: String, Codable, Sendable { case manual, device }
    enum Freshness: Equatable, Sendable { case manual, fresh, stale, invalid }

    var text: String
    let timestamp: Date?
    let horizontalAccuracy: Double?
    let provenance: Provenance

    static func manual(text: String) -> Self {
        Self(text: text, timestamp: nil, horizontalAccuracy: nil, provenance: .manual)
    }

    func freshness(at now: Date = Date(), maximumAge: TimeInterval = 120) -> Freshness {
        if provenance == .manual { return .manual }
        guard let timestamp, let horizontalAccuracy, horizontalAccuracy.isFinite,
              horizontalAccuracy >= 0, timestamp.timeIntervalSince1970.isFinite else { return .invalid }
        let age = now.timeIntervalSince(timestamp)
        guard age >= -10 else { return .invalid }
        return age <= maximumAge ? .fresh : .stale
    }

    func statusText(at now: Date = Date()) -> String {
        switch freshness(at: now) {
        case .manual: return AppLocalization.string("手动填写的位置")
        case .invalid: return AppLocalization.string("定位结果无效，请重新定位")
        case .stale: return String(format: AppLocalization.string("历史定位（%@），请核对"), Formatters.dateTime.string(from: timestamp ?? now))
        case .fresh:
            return String(format: AppLocalization.string("本次定位 · 精度约 %lld 米"), Int64(min(horizontalAccuracy ?? 0, 1_000_000)))
        }
    }
}

@MainActor
final class WatermarkCameraLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationText = ""
    @Published var statusText = ""
    @Published private(set) var snapshot: WatermarkLocationSnapshot?
    @Published private(set) var isRequesting = false
    @Published private(set) var requestError: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var geocodingGeneration = UUID()
    private var pendingExplicitRequest = false
    private var requestTimeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        guard !isRequesting else { return }
        requestTimeout?.cancel()
        requestTimeout = nil
        requestError = nil
        geocodingGeneration = UUID()
        geocoder.cancelGeocode()
        pendingExplicitRequest = true
        isRequesting = true
        guard CLLocationManager.locationServicesEnabled() else {
            finishRequest(message: AppLocalization.string("wm_camera_location_service_disabled"))
            return
        }
        continueExplicitRequest()
    }

    func cancelRequest() {
        requestTimeout?.cancel()
        requestTimeout = nil
        requestError = nil
        geocodingGeneration = UUID()
        pendingExplicitRequest = false
        isRequesting = false
        statusText = ""
        geocoder.cancelGeocode()
    }

    private func continueExplicitRequest() {
        guard pendingExplicitRequest else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            statusText = AppLocalization.string("wm_camera_location_requesting_permission")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = AppLocalization.string("wm_camera_location_fetching")
            scheduleTimeoutIfNeeded()
            manager.requestLocation()
        case .denied, .restricted:
            finishRequest(message: AppLocalization.string("wm_camera_location_permission_disabled"))
        @unknown default:
            finishRequest(message: AppLocalization.string("wm_camera_location_unavailable"))
        }
    }

    private func scheduleTimeoutIfNeeded() {
        guard requestTimeout == nil else { return }
        let generation = geocodingGeneration
        requestTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.geocodingGeneration == generation, self.isRequesting else { return }
            self.finishRequest(message: AppLocalization.string("定位超时，请重试；已保留原位置。"))
        }
    }

    private func finishRequest(message: String) {
        // Invalidate before canceling geocoding: its completion can arrive after cancellation.
        geocodingGeneration = UUID()
        requestTimeout?.cancel()
        requestTimeout = nil
        geocoder.cancelGeocode()
        pendingExplicitRequest = false
        isRequesting = false
        requestError = message
        statusText = message
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.continueExplicitRequest() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // CLLocation is immutable. Preserve the fix, rather than recreating it with a fresh timestamp.
        guard let location = locations.max(by: { $0.timestamp < $1.timestamp }) else { return }
        Task { @MainActor in self.resolveLocation(location) }
    }

    private func resolveLocation(_ location: CLLocation) {
        guard pendingExplicitRequest else { return }
        pendingExplicitRequest = false
        let generation = geocodingGeneration
        let coordinate = location.coordinate
        let fix = WatermarkLocationSnapshot(
            text: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            provenance: .device
        )
        guard CLLocationCoordinate2DIsValid(coordinate), fix.freshness() != .invalid else {
            finishRequest(message: AppLocalization.string("定位结果无效，请重新定位"))
            return
        }
        snapshot = fix
        locationText = fix.text
        statusText = AppLocalization.string("正在获取位置地址…")
        // A stale fix is usable only as a clearly identified historical value.
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let readable = placemarks?.first.map { placemark in
                [placemark.administrativeArea, placemark.locality, placemark.subLocality,
                 placemark.thoroughfare, placemark.name]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
            var resolvedFix = fix
            if let readable, !readable.isEmpty { resolvedFix.text = readable }
            Task { @MainActor in
                guard let self, self.geocodingGeneration == generation else { return }
                self.snapshot = resolvedFix
                self.locationText = resolvedFix.text
                self.isRequesting = false
                self.requestTimeout?.cancel()
                self.requestTimeout = nil
                self.requestError = nil
                self.statusText = resolvedFix.statusText()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.pendingExplicitRequest else { return }
            self.finishRequest(message: AppLocalization.string("wm_camera_location_failed"))
        }
    }
}
