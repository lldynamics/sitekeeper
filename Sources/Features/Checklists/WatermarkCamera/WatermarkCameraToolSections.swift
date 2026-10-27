import SwiftUI

struct WatermarkTemplateSection: View {
    @Binding var templateRaw: String

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CameraWatermarkTemplate.allCases, id: \.rawValue) { template in
                        let isSelected = templateRaw == template.rawValue
                        Button {
                            templateRaw = template.rawValue
                        } label: {
                            WatermarkTemplateChip(
                                title: template.displayName,
                                systemImage: template.icon,
                                isSelected: isSelected
                            )
                        }
                    }
                }
            }
        } header: {
            Label(AppLocalization.string("wm_camera_template_section_title"), systemImage: "rectangle.and.pencil.and.ellipsis")
        }
    }
}

struct WatermarkCaptureSection: View {
    let openCamera: () -> Void

    var body: some View {
        Section {
            Button(action: openCamera) {
                Label(AppLocalization.string("wm_camera_capture_button"), systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(AppProminentButtonStyle())
        }
    }
}

struct WatermarkInfoSection: View {
    @Binding var tag: String
    @Binding var photographer: String
    @Binding var locationText: String
    let locationStatusText: String
    let requestLocation: () -> Void

    var body: some View {
        Section {
            TextField(AppLocalization.string("wm_camera_tag_field"), text: $tag)
            TextField(AppLocalization.string("wm_camera_photographer_field"), text: $photographer)
            HStack {
                TextField(AppLocalization.string("wm_camera_location_field"), text: $locationText)
                Button(action: requestLocation) {
                    Image(systemName: "location.fill").visibleIconStyle()
                }
                .buttonStyle(AppIconButtonStyle())
            }
            if !locationStatusText.isEmpty {
                Text(locationStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label(AppLocalization.string("wm_camera_info_section_title"), systemImage: "info.circle")
        }
    }
}

private struct WatermarkTemplateChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.appPrimaryAction : Color(uiColor: .secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}
