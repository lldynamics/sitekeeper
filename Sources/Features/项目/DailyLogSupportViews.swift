import SwiftUI
import UIKit
import Foundation

enum DailyLogMode: String, CaseIterable {
    case list
    case calendar
    case gallery

    var displayName: String {
        switch self {
        case .list: String(localized: "列表")
        case .calendar: String(localized: "日历")
        case .gallery: String(localized: "照片墙")
        }
    }
}

struct CalendarDayCell: View {
    let date: Date?
    let isSelected: Bool
    let isToday: Bool
    let logs: [DailyLog]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if let date {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.caption.weight(isSelected || isToday ? .bold : .regular))
                        .foregroundStyle(isSelected ? .white : .primary)
                    HStack(spacing: 2) {
                        if !logs.isEmpty {
                            Circle()
                                .fill(isSelected ? Color.white : Color.appPrimaryAction)
                                .frame(width: 5, height: 5)
                            if logs.contains(where: { !$0.photoAttachments.isEmpty }) {
                                Image(systemName: "camera.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(isSelected ? .white : Color.appDoc)
                            }
                        }
                    }
                    .frame(height: 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday && !isSelected ? Color.appStrokeWarning : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(date == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var backgroundColor: Color {
        if date == nil { return .clear }
        if isSelected { return .appPrimaryAction }
        if !logs.isEmpty { return Color.appPrimarySurfaceSubtle }
        return Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var accessibilityLabel: String {
        guard let date else { return "" }
        return DailyLogDateFormatters.accessibilityDayTitle.string(from: date)
    }

    private var accessibilityValue: String {
        guard date != nil else { return "" }
        var parts = [String(format: String(localized: "%lld 条"), Int64(logs.count))]
        if isToday {
            parts.append(String(localized: "今天"))
        }
        if isSelected {
            parts.append(String(localized: "已选中"))
        }
        if logs.contains(where: { !$0.photoAttachments.isEmpty }) {
            parts.append(String(localized: "照片"))
        }
        return parts.joined(separator: "，")
    }

    private var accessibilityIdentifier: String {
        guard let date else { return "daily-log-calendar-placeholder" }
        return "daily-log-calendar-day-\(Formatters.date.string(from: date))"
    }
}

struct PhotoDraft: Identifiable {
    var id = UUID()
    var data: Data
    var note: String = ""
    var tag: PhotoTag = .general
}

struct DailyLogSeedPhoto {
    var data: Data
    var note: String
    var tag: PhotoTag
    var capturedAt: Date?

    var photoDraft: PhotoDraft {
        PhotoDraft(data: data, note: note, tag: tag)
    }
}

struct PhotoWallItem: Identifiable {
    var id: UUID { photo.id }
    let logId: UUID
    let logDate: String
    let projectId: UUID?
    let photo: LogPhoto
}

struct SelectedPhotoContext: Identifiable {
    var id: String { "\(logId.uuidString)-\(photoId.uuidString)" }
    let logId: UUID
    let photoId: UUID
    let legacyFileName: String
}

struct PhotoDetailSheet: View {
    let context: SelectedPhotoContext
    let allLogs: [DailyLog]
    let onSave: (String, PhotoTag) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var tag: PhotoTag = .general
    @State private var showDeleteConfirm = false
    @State private var previewImage: UIImage?
    @State private var didAttemptLoadImage = false

    private var selectedPhoto: LogPhoto? {
        allLogs.first(where: { $0.id == context.logId })?
            .photoAttachments
            .first(where: { $0.id == context.photoId || $0.fileName == context.legacyFileName })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "照片预览")) {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                    } else if !didAttemptLoadImage {
                        ProgressView(String(localized: "加载中…"))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(String(localized: "图片已丢失或不可读取"))
                            .foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "备注")) {
                    Picker(String(localized: "照片标签"), selection: $tag) {
                        ForEach(PhotoTag.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "现场备注"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button(String(localized: "保存备注")) {
                        onSave(note, tag)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    Button(String(localized: "删除照片"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(String(localized: "照片详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
            .onAppear {
                note = selectedPhoto?.note ?? ""
                tag = selectedPhoto?.tag ?? .general
            }
            .task(id: selectedPhoto?.fileName) {
                await loadPreviewImage()
            }
            .alert(String(localized: "删除这张照片？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "删除"), role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "该操作仅删除当前照片，不会删除整条日志。"))
            }
        }
    }

    private func loadPreviewImage() async {
        didAttemptLoadImage = false
        previewImage = nil
        guard let fileName = selectedPhoto?.fileName else {
            didAttemptLoadImage = true
            return
        }
        if let image = await ImageDownsampleService.downsampledImageAsync(
            at: PhotoStorage.fileURL(for: fileName),
            maxPixelSize: 2_400,
            source: "DailyLogPhotoDetailSheet.loadPreviewImage"
        ) {
            guard !Task.isCancelled, selectedPhoto?.fileName == fileName else { return }
            previewImage = image
            didAttemptLoadImage = true
            return
        }
        guard !Task.isCancelled, selectedPhoto?.fileName == fileName else { return }
        if let thumbnail = await ImageDownsampleService.downsampledImageAsync(
            at: PhotoStorage.thumbnailURL(for: fileName),
            maxPixelSize: 1_200,
            source: "DailyLogPhotoDetailSheet.loadPreviewThumbnail"
        ) {
            guard !Task.isCancelled, selectedPhoto?.fileName == fileName else { return }
            previewImage = thumbnail
        }
        guard !Task.isCancelled, selectedPhoto?.fileName == fileName else { return }
        didAttemptLoadImage = true
    }
}

/// 根据当前时间简单推测天气（非联网，用于默认值）
func autoWeatherNow() -> String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 6..<12: return String(localized: "晴")
    case 12..<18: return String(localized: "多云")
    case 18..<21: return String(localized: "阴")
    default: return String(localized: "晴")
    }
}
