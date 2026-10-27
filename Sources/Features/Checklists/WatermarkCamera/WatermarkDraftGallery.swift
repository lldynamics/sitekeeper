import SwiftUI

struct WatermarkDraftGallery: View {
    let photos: [WatermarkCapturedPhoto]
    @Binding var selectedPhotoID: UUID?
    @Binding var selectedIDs: Set<UUID>

    private var focused: WatermarkCapturedPhoto? { photos.first { $0.id == selectedPhotoID } ?? photos.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let photo = focused {
                Image(uiImage: photo.thumbnail).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .accessibilityLabel(AppLocalization.string("所选水印照片预览"))
                Text(photo.context.projectName ?? AppLocalization.string("未指定项目")).font(.headline)
                Text(WatermarkCameraTextBuilder.capturedPhotoMetaText(capturedAt: photo.capturedAt, template: photo.context.template, tag: photo.context.tag))
                    .font(.caption).foregroundStyle(.secondary)
                Text(status(photo)).font(.caption).foregroundStyle(photo.isPersisted ? Color.secondary : Color.red)
                    .accessibilityIdentifier("watermark-draft-status")
                if let failure = photo.albumFailure ?? photo.archiveFailure { Text(failure).font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Text(String(format: AppLocalization.string("已选 %lld / %lld 张"), selectedIDs.count, photos.count)).font(.subheadline)
                Spacer()
                Button(AppLocalization.string("全选")) { selectedIDs = Set(photos.map(\.id)) }
                Button(AppLocalization.string("取消选择")) { selectedIDs = [] }
            }
            .buttonStyle(.borderless)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(photos) { photo in
                        VStack(spacing: 6) {
                            Button { selectedPhotoID = photo.id } label: {
                                Image(uiImage: photo.thumbnail).resizable().scaledToFill()
                                    .frame(width: 92, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused?.id == photo.id ? Color.accentColor : Color.clear, lineWidth: 3))
                            }.accessibilityLabel("\(AppLocalization.string("预览照片")) \(photo.context.projectName ?? "") \(Formatters.dateTime.string(from: photo.capturedAt))")
                            Button {
                                if selectedIDs.contains(photo.id) { selectedIDs.remove(photo.id) } else { selectedIDs.insert(photo.id) }
                            } label: {
                                Label(AppLocalization.string("选择"), systemImage: selectedIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                            }.font(.caption).accessibilityValue(selectedIDs.contains(photo.id) ? AppLocalization.string("已选择") : AppLocalization.string("未选择"))
                        }.buttonStyle(.plain)
                    }
                }.padding(3)
            }
        }
    }

    private func status(_ photo: WatermarkCapturedPhoto) -> String {
        let saved = photo.isPersisted ? AppLocalization.string("已暂存") : AppLocalization.string("暂存失败，请重试")
        let album = photo.albumStatus == .completed ? AppLocalization.string("已存相册") : AppLocalization.string("待存相册")
        let archive = photo.archiveStatus == .completed ? AppLocalization.string("已归档") : AppLocalization.string("待归档")
        return [saved, album, archive].joined(separator: " · ")
    }
}
