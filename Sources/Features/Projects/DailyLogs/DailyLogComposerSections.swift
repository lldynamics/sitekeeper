import SwiftUI
import PhotosUI
import UIKit

struct DailyLogWatermarkPhotoSection: View {
    @Binding var cameraPhotoTag: PhotoTag
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var photoDrafts: [PhotoDraft]
    let isImporting: Bool
    let onOpenCamera: () -> Void

    @State private var activeEditingPhotoId: UUID?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        Section {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Picker(AppLocalization.string("拍照标签"), selection: $cameraPhotoTag) {
                    ForEach(PhotoTag.allCases, id: \.self) { tag in
                        Text(tag.displayName).tag(tag)
                    }
                }
                Button {
                    onOpenCamera()
                } label: {
                    Label(AppLocalization.string("现场拍照打卡"), systemImage: "camera.fill")
                }
                .disabled(photoDrafts.count >= 6)
            }

            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                Label(AppLocalization.string("从相册选择照片"), systemImage: "photo.on.rectangle")
            }
            .disabled(isImporting || photoDrafts.count >= 6)
            .accessibilityIdentifier("daily-log-compose-photo-picker")

            if isImporting {
                ProgressView(AppLocalization.string("正在处理照片…"))
                    .accessibilityIdentifier("daily-log-compose-photo-loading")
            }

            // 紧凑九宫格缩略图视图
            if !photoDrafts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(format: AppLocalization.string("已选现场照片（%lld/6）"), Int64(photoDrafts.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(photoDrafts) { draft in
                            photoThumbnailCell(draft: draft)
                        }
                    }

                    // 展开单张照片的备注与标签编辑
                    if let activeId = activeEditingPhotoId,
                       let draftIndex = photoDrafts.firstIndex(where: { $0.id == activeId }) {
                        activePhotoDetailEditor(index: draftIndex)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(AppLocalization.string("现场照片留痕"))
        }
    }

    private func photoThumbnailCell(draft: PhotoDraft) -> some View {
        let isEditing = activeEditingPhotoId == draft.id
        return ZStack(alignment: .topTrailing) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if activeEditingPhotoId == draft.id {
                        activeEditingPhotoId = nil
                    } else {
                        activeEditingPhotoId = draft.id
                    }
                }
            } label: {
                ZStack(alignment: .bottomLeading) {
                    if let uiImage = UIImage(data: draft.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Rectangle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // 底部半透明标签条
                    HStack(spacing: 4) {
                        Text(draft.tag.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
                }
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isEditing ? Color.appPrimaryAction : Color.clear, lineWidth: 2)
            )

            // 右上角删除按钮
            Button {
                photoDrafts.removeAll { $0.id == draft.id }
                if activeEditingPhotoId == draft.id { activeEditingPhotoId = nil }
                AppHaptics.impact(.light)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white, Color.red.opacity(0.85))
                    .background(Circle().fill(Color.black.opacity(0.3)))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 10, y: -10)
        }
    }

    @ViewBuilder
    private func activePhotoDetailEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppLocalization.string("编辑所选照片属性"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(AppLocalization.string("收起")) {
                    withAnimation(.snappy(duration: 0.2)) {
                        activeEditingPhotoId = nil
                    }
                }
                .font(.caption)
            }

            Picker(AppLocalization.string("照片标签"), selection: $photoDrafts[index].tag) {
                ForEach(PhotoTag.allCases, id: \.self) { tag in
                    Text(tag.displayName).tag(tag)
                }
            }
            .pickerStyle(.menu)

            TextField(AppLocalization.string("输入照片备注说明…"), text: $photoDrafts[index].note)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
