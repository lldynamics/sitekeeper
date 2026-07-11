import SwiftUI

struct WatermarkCameraSettingsSection: View {
    @Binding var exportQuality: WatermarkExportQuality
    @Binding var showGrid: Bool
    @Binding var flashEnabled: Bool
    @Binding var burstCount: Int
    let boundedBurstCount: Int

    var body: some View {
        Section {
            DisclosureGroup {
                Picker(String(localized: "wm_camera_export_quality_picker"), selection: $exportQuality) {
                    ForEach(WatermarkExportQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                Toggle(String(localized: "wm_camera_show_grid_toggle"), isOn: $showGrid)
                Toggle(String(localized: "wm_camera_flash_default_toggle"), isOn: $flashEnabled)
                Stepper(
                    String(
                        format: String(localized: "wm_camera_burst_count_stepper_format"),
                        boundedBurstCount
                    ),
                    value: $burstCount,
                    in: 1...5
                )
            } label: {
                Label(String(localized: "wm_camera_settings_section_title"), systemImage: "camera.fill")
            }
        }
    }
}

struct WatermarkAutoSaveSection: View {
    @Binding var autoSaveToAlbum: Bool
    @Binding var autoOpenLogDraft: Bool

    var body: some View {
        Section {
            Toggle(String(localized: "wm_camera_auto_save_album_toggle"), isOn: $autoSaveToAlbum)
            Toggle(String(localized: "wm_camera_auto_open_log_draft_toggle"), isOn: $autoOpenLogDraft)
        }
    }
}
