import SwiftUI
import UIKit
import Foundation

enum DailyLogMode: String, CaseIterable {
    case list
    case calendar
    case gallery

    var displayName: String {
        switch self {
        case .list: "列表"
        case .calendar: "日历"
        case .gallery: "照片墙"
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
                                .fill(isSelected ? Color.white : Color.orange)
                                .frame(width: 5, height: 5)
                            if logs.contains(where: { !$0.photoAttachments.isEmpty }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(isSelected ? .white : .blue)
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
    }

    private var backgroundColor: Color {
        if date == nil { return .clear }
        if isSelected { return .orange }
        if !logs.isEmpty { return Color.appPrimarySurfaceSubtle }
        return Color(uiColor: .secondarySystemGroupedBackground)
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

    private var selectedPhoto: LogPhoto? {
        allLogs.first(where: { $0.id == context.logId })?
            .photoAttachments
            .first(where: { $0.id == context.photoId || $0.fileName == context.legacyFileName })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("照片预览") {
                    if let fileName = selectedPhoto?.fileName,
                       let data = PhotoStorage.data(for: fileName),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                    } else if let image = PhotoStorage.thumbnail(for: selectedPhoto?.fileName) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("图片已丢失或不可读取")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("备注") {
                    Picker("照片标签", selection: $tag) {
                        ForEach(PhotoTag.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("现场备注", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button("保存备注") {
                        onSave(note, tag)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    Button("删除照片", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("照片详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                note = selectedPhoto?.note ?? ""
                tag = selectedPhoto?.tag ?? .general
            }
            .alert("删除这张照片？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("该操作仅删除当前照片，不会删除整条日志。")
            }
        }
    }
}

/// 根据当前时间简单推测天气（非联网，用于默认值）
func autoWeatherNow() -> String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 6..<12: return "晴"
    case 12..<18: return "多云"
    case 18..<21: return "阴"
    default: return "晴"
    }
}
