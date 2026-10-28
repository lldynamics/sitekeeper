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
    var isRequesting: Bool = false
    let requestLocation: () -> Void

    var body: some View {
        Section {
            TextField(AppLocalization.string("wm_camera_tag_field"), text: $tag)
            TextField(AppLocalization.string("wm_camera_photographer_field"), text: $photographer)
            HStack {
                TextField(AppLocalization.string("wm_camera_location_field"), text: $locationText)
                Button(action: requestLocation) {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Image(systemName: "location.fill").visibleIconStyle()
                    }
                }
                .buttonStyle(AppIconButtonStyle())
                .disabled(isRequesting)
                .accessibilityLabel(isRequesting ? AppLocalization.string("正在定位") : AppLocalization.string("获取当前位置"))
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

struct WatermarkEngineeringSection: View {
    let template: CameraWatermarkTemplate
    @Binding var workSection: String
    @Binding var floor: String
    @Binding var process: String
    @Binding var issueNumber: String
    @Binding var completedQuantity: String
    @Binding var receiptNote: String

    var body: some View {
        Section {
            TextField(AppLocalization.string("施工段（如 1 号楼东区）"), text: $workSection)
            if template != .receipt {
                TextField(AppLocalization.string("楼层/部位（如 3 层走廊）"), text: $floor)
            }
            switch template {
            case .constructionLog:
                TextField(AppLocalization.string("施工工序（如 桥架安装）"), text: $process)
            case .rectification:
                TextField(AppLocalization.string("问题编号（如 ZG-001）"), text: $issueNumber)
                TextField(AppLocalization.string("整改工序/内容"), text: $process)
            case .paymentProof:
                TextField(AppLocalization.string("完成工程量（请填写数值与单位）"), text: $completedQuantity)
                TextField(AppLocalization.string("施工工序"), text: $process)
            case .receipt:
                TextField(AppLocalization.string("票据说明（如 材料采购收据）"), text: $receiptNote)
            }
        } header: {
            Label(String(format: AppLocalization.string("%@信息"), template.displayName), systemImage: template.icon)
        } footer: {
            Text(AppLocalization.string("按现场实际填写；未填写的项目会在完整水印中标明。"))
        }
    }
}
