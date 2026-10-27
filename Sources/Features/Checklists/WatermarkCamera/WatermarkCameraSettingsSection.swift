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
                Picker(AppLocalization.string("wm_camera_export_quality_picker"), selection: $exportQuality) {
                    ForEach(WatermarkExportQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                Toggle(AppLocalization.string("wm_camera_show_grid_toggle"), isOn: $showGrid)
                Toggle(AppLocalization.string("wm_camera_flash_default_toggle"), isOn: $flashEnabled)
                Stepper(
                    String(
                        format: AppLocalization.string("wm_camera_burst_count_stepper_format"),
                        boundedBurstCount
                    ),
                    value: $burstCount,
                    in: 1...5
                )
            } label: {
                Label(AppLocalization.string("wm_camera_settings_section_title"), systemImage: "camera.fill")
            }
        }
    }
}

struct WatermarkAutoSaveSection: View {
    @Binding var autoSaveToAlbum: Bool
    @Binding var autoOpenLogDraft: Bool

    var body: some View {
        Section {
            Toggle(AppLocalization.string("wm_camera_auto_save_album_toggle"), isOn: $autoSaveToAlbum)
            Toggle(AppLocalization.string("wm_camera_auto_open_log_draft_toggle"), isOn: $autoOpenLogDraft)
        }
    }
}

struct WatermarkStyleSection: View {
    @Binding var style: WatermarkCameraStyle

    var body: some View {
        Section {
            Picker(AppLocalization.string("水印位置"), selection: $style.position) {
                ForEach(WatermarkCameraStyle.Position.allCases, id: \.self) { position in
                    Text(position.displayName).tag(position)
                }
            }
            Picker(AppLocalization.string("水印内容"), selection: $style.detail) {
                ForEach(WatermarkCameraStyle.Detail.allCases, id: \.self) { detail in
                    Text(detail.displayName).tag(detail)
                }
            }
            Text(AppLocalization.string("精简模式显示工程、拍摄时间与当前模板的主要记录。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label(AppLocalization.string("水印样式"), systemImage: "text.below.photo")
        }
    }
}
