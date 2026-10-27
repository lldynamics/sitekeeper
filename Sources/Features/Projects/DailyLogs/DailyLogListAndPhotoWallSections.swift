import SwiftUI

struct DailyLogEntryRow: View {
    let log: DailyLog
    let projectName: String?
    let linkedMethodTitles: [String]
    let onOpenPhoto: (SelectedPhotoContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack {
                Text(log.date).font(.body.weight(.medium))
                Spacer()
                Text(log.weather.isEmpty ? AppLocalization.string("天气待填写") : log.weather).font(.caption).foregroundStyle(.secondary)
                Text(log.workers).font(.caption).foregroundStyle(.secondary)
            }
            if let projectName {
                Text(projectName).font(.caption2).foregroundStyle(Color.appDoc)
            }
            Text(log.content).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            if !log.safety.isEmpty {
                Label(log.safety, systemImage: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !log.materials.isEmpty {
                Label(log.materials, systemImage: "shippingbox.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !log.tomorrowPlan.isEmpty {
                Label(log.tomorrowPlan, systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !log.qualityIssue.isEmpty || !log.rectification.isEmpty {
                Label(log.qualityIssue.isEmpty ? log.rectification : log.qualityIssue, systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption)
                    .foregroundStyle(.appRisk)
                    .lineLimit(2)
            }
            if !linkedMethodTitles.isEmpty {
                Label(linkedMethodTitles.joined(separator: " · "), systemImage: "book.pages")
                    .font(.caption)
                    .foregroundStyle(Color.appPrimaryAction)
                    .lineLimit(2)
            }
            if !log.photoAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppSpacing.tight) {
                        ForEach(log.photoAttachments) { photo in
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    onOpenPhoto(SelectedPhotoContext(logId: log.id, photoId: photo.id, legacyFileName: photo.fileName))
                                } label: {
                                    AsyncPhotoThumbnailImageView(fileName: photo.fileName) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 110, height: 82)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(uiColor: .secondarySystemFill))
                                            .frame(width: 110, height: 82)
                                            .overlay {
                                                Image(systemName: "photo")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(format: AppLocalization.string("查看日志照片，标签 %@"), photo.tag.displayName))
                                .accessibilityHint(AppLocalization.string("打开照片详情"))
                                Text(photo.tag.displayName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appDoc)
                                if !photo.note.isEmpty {
                                    Text(photo.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(width: 110, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct DailyLogPhotoWallSection: View {
    let items: [PhotoWallItem]
    let projects: [Project]
    @Binding var photoTagFilter: PhotoTag?
    @Binding var isPhotoSelecting: Bool
    @Binding var selectedPhotoKeys: Set<String>
    @Binding var batchPhotoTag: PhotoTag
    let hasRectificationPair: (UUID) -> Bool
    let selectionKey: (PhotoWallItem) -> String
    let onToggleSelection: (PhotoWallItem) -> Void
    let onOpenPhoto: (SelectedPhotoContext) -> Void
    let onApplyBatchTag: () -> Void
    let onExport: ([PhotoWallItem]) -> Void

    var body: some View {
        Section(AppLocalization.string("照片墙")) {
            HStack {
                Picker(AppLocalization.string("标签"), selection: $photoTagFilter) {
                    Text(AppLocalization.string("全部")).tag(nil as PhotoTag?)
                    ForEach(PhotoTag.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item as PhotoTag?)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button(isPhotoSelecting ? AppLocalization.string("结束批量") : AppLocalization.string("批量操作")) {
                    isPhotoSelecting.toggle()
                    if !isPhotoSelecting {
                        selectedPhotoKeys.removeAll()
                    }
                }
                .font(.caption)
            }
            if isPhotoSelecting {
                HStack {
                    Picker(AppLocalization.string("批量标签"), selection: $batchPhotoTag) {
                        ForEach(PhotoTag.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    Button(String(format: AppLocalization.string("应用到%lld张"), Int64(selectedPhotoKeys.count))) {
                        onApplyBatchTag()
                    }
                    .disabled(selectedPhotoKeys.isEmpty)
                    Button(AppLocalization.string("清空选择")) {
                        selectedPhotoKeys.removeAll()
                    }
                    .disabled(selectedPhotoKeys.isEmpty)
                }
                .font(.caption)
            }
            Button {
                onExport(items)
            } label: {
                Label(AppLocalization.string("按当前项目/筛选导出照片页"), systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .disabled(items.isEmpty)

            if items.isEmpty {
                ContentUnavailableView(
                    AppLocalization.string("暂无现场照片"),
                    systemImage: "photo.on.rectangle",
                    description: Text(AppLocalization.string("添加日志照片后可在这里按标签查看。"))
                )
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.tight), count: 3), spacing: AppSpacing.normal) {
                    ForEach(items) { item in
                        Button {
                            if isPhotoSelecting {
                                onToggleSelection(item)
                            } else {
                                onOpenPhoto(SelectedPhotoContext(logId: item.logId, photoId: item.photo.id, legacyFileName: item.photo.fileName))
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncPhotoThumbnailImageView(fileName: item.photo.fileName) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 88)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            if isPhotoSelecting {
                                                let isSelected = selectedPhotoKeys.contains(selectionKey(item))
                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(isSelected ? Color.appPrimaryAction : .white)
                                                    .padding(4)
                                            }
                                        }
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(uiColor: .secondarySystemFill))
                                        .frame(height: 88)
                                        .overlay(alignment: .topTrailing) {
                                            if isPhotoSelecting {
                                                let isSelected = selectedPhotoKeys.contains(selectionKey(item))
                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(isSelected ? Color.appPrimaryAction : .secondary)
                                                    .padding(4)
                                            }
                                        }
                                }
                                Text(item.logDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .appListSecondaryTextLayout(lines: 1)
                                Text(item.photo.tag.displayName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appDoc)
                                    .appListPrimaryTextLayout(lines: 2)
                                if hasRectificationPair(item.logId),
                                   item.photo.tag == .rectificationBefore || item.photo.tag == .rectificationAfter {
                                    Text(AppLocalization.string("已配对"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.appSuccess)
                                }
                                if !item.photo.note.isEmpty {
                                    Text(item.photo.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .appListSecondaryTextLayout()
                                }
                                if let project = item.projectId.flatMap({ pid in projects.first(where: { $0.id == pid }) }) {
                                    Text(project.name)
                                        .font(.caption2)
                                        .foregroundStyle(Color.appDoc)
                                        .appListSecondaryTextLayout()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.logDate)，\(item.photo.tag.displayName)")
                        .accessibilityHint(isPhotoSelecting ? AppLocalization.string("双击切换选择状态") : AppLocalization.string("双击查看照片详情"))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
