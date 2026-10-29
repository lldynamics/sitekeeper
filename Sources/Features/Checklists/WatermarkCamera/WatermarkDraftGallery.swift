import SwiftUI
import UIKit

struct WatermarkDraftGallery: View {
    let photos: [WatermarkCapturedPhoto]
    @Binding var selectedPhotoID: UUID?
    @Binding var selectedIDs: Set<UUID>
    var logStatuses: [UUID: String] = [:]

    private enum DateFilter: String, CaseIterable { case all, today, week }
    private enum DeliveryFilter: String, CaseIterable { case all, pending, completed, failed }
    @State private var multiSelect = false
    @State private var dateFilter: DateFilter = .all
    @State private var deliveryFilter: DeliveryFilter = .all
    @State private var projectFilter = "all"
    @State private var showingDetail = false

    private var visible: [WatermarkCapturedPhoto] {
        photos.filter { photo in
            let dateMatches: Bool
            switch dateFilter {
            case .all: dateMatches = true
            case .today: dateMatches = Calendar.current.isDateInToday(photo.capturedAt)
            case .week: dateMatches = photo.capturedAt >= (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast)
            }
            let projectMatches = projectFilter == "all" || projectFilter == (photo.projectId?.uuidString ?? "unlinked")
            let deliveryMatches: Bool
            switch deliveryFilter {
            case .all: deliveryMatches = true
            case .pending: deliveryMatches = photo.albumStatus == .pending || photo.archiveStatus == .pending
            case .completed: deliveryMatches = photo.albumStatus == .completed && photo.archiveStatus == .completed
            case .failed: deliveryMatches = !photo.isPersisted || photo.albumStatus == .failed || photo.archiveStatus == .failed
            }
            return dateMatches && projectMatches && deliveryMatches
        }
    }
    private var focused: WatermarkCapturedPhoto? { visible.first { $0.id == selectedPhotoID } ?? visible.first }
    private var projects: [(String, String)] {
        var seen = Set<String>()
        return photos.compactMap { photo in
            let key = photo.projectId?.uuidString ?? "unlinked"
            guard seen.insert(key).inserted else { return nil }
            return (key, photo.context.projectName ?? AppLocalization.string("未指定项目"))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filters
            if let photo = focused {
                Button { showingDetail = true } label: {
                    WatermarkDraftImageView(photo: photo, maxPixelSize: 1000)
                        .frame(maxWidth: .infinity, maxHeight: 280)
                }.buttonStyle(.plain).accessibilityLabel(AppLocalization.string("打开照片大图"))
                Text(photo.context.projectName ?? AppLocalization.string("未指定项目")).font(.headline)
                Text(WatermarkCameraTextBuilder.capturedPhotoMetaText(capturedAt: photo.capturedAt, template: photo.context.template, tag: photo.context.tag))
                    .font(.caption).foregroundStyle(.secondary)
                Text(status(photo)).font(.caption).foregroundStyle(photo.isPersisted ? Color.secondary : Color.red)
                    .accessibilityIdentifier("watermark-draft-status")
                if let logStatus = logStatuses[photo.id] { Text(logStatus).font(.caption).foregroundStyle(.secondary) }
                if let failure = photo.albumFailure ?? photo.archiveFailure { Text(failure).font(.caption).foregroundStyle(.red) }
                if multiSelect {
                    Text(selectedIDs.contains(photo.id) ? AppLocalization.string("当前预览已选中") : AppLocalization.string("当前预览未选中，批量操作仅处理勾选的照片"))
                        .font(.caption.weight(.medium))
                }
            } else {
                Text(AppLocalization.string("没有符合条件的照片，请调整筛选条件。"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            }
            Toggle(AppLocalization.string("多选照片"), isOn: $multiSelect)
            if multiSelect {
                HStack {
                    Text(String(format: AppLocalization.string("已选 %lld / %lld 张"), selectedIDs.count, visible.count)).font(.subheadline)
                    Spacer()
                    Button(AppLocalization.string("全选")) { selectedIDs = Set(visible.map(\.id)) }
                    Button(AppLocalization.string("取消选择")) { selectedIDs = [] }
                }.buttonStyle(.borderless)
            } else {
                Text(AppLocalization.string("单张模式：操作当前预览照片")).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(visible) { photo in
                        Button {
                            selectedPhotoID = photo.id
                            if multiSelect {
                                if selectedIDs.contains(photo.id) { selectedIDs.remove(photo.id) } else { selectedIDs.insert(photo.id) }
                            } else { selectedIDs = [photo.id] }
                        } label: {
                            VStack(spacing: 6) {
                                WatermarkDraftImageView(photo: photo, maxPixelSize: 240)
                                    .frame(width: 92, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused?.id == photo.id ? Color.accentColor : Color.clear, lineWidth: 3))
                                if multiSelect {
                                    Label(AppLocalization.string("选择"), systemImage: selectedIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle").font(.caption)
                                }
                            }
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(AppLocalization.string(multiSelect ? "选择照片" : "预览照片")) \(photo.context.projectName ?? "") \(Formatters.dateTime.string(from: photo.capturedAt))")
                            .accessibilityValue(selectedIDs.contains(photo.id) ? AppLocalization.string("已选择") : AppLocalization.string("未选择"))
                    }
                }.padding(3)
            }
        }
        .onAppear { reconcileSelection() }
        .onChange(of: visible.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: multiSelect) { _, _ in reconcileSelection() }
        .onChange(of: selectedPhotoID) { _, _ in reconcileSelection() }
        .onChange(of: selectedIDs) { _, _ in
            if !multiSelect { reconcileSelection() }
        }
        .fullScreenCover(isPresented: $showingDetail) {
            if let photo = focused { WatermarkDraftZoomView(photo: photo) }
        }
    }

    private var filters: some View {
        HStack {
            Menu {
                Button(AppLocalization.string("全部日期")) { dateFilter = .all }
                Button(AppLocalization.string("今天")) { dateFilter = .today }
                Button(AppLocalization.string("最近 7 天")) { dateFilter = .week }
            } label: { Label(dateFilter == .all ? AppLocalization.string("全部日期") : (dateFilter == .today ? AppLocalization.string("今天") : AppLocalization.string("最近 7 天")), systemImage: "calendar") }
            Menu {
                Button(AppLocalization.string("全部项目")) { projectFilter = "all" }
                ForEach(projects, id: \.0) { project in Button(project.1) { projectFilter = project.0 } }
            } label: { Label(projects.first { $0.0 == projectFilter }?.1 ?? AppLocalization.string("全部项目"), systemImage: "building.2") }
            Menu {
                Button(AppLocalization.string("全部状态")) { deliveryFilter = .all }
                Button(AppLocalization.string("待处理")) { deliveryFilter = .pending }
                Button(AppLocalization.string("已完成")) { deliveryFilter = .completed }
                Button(AppLocalization.string("失败")) { deliveryFilter = .failed }
            } label: { Label(deliveryFilterTitle, systemImage: "line.3.horizontal.decrease.circle") }
        }.font(.caption).buttonStyle(.borderless)
    }
    private var deliveryFilterTitle: String {
        switch deliveryFilter {
        case .all: AppLocalization.string("全部状态")
        case .pending: AppLocalization.string("待处理")
        case .completed: AppLocalization.string("已完成")
        case .failed: AppLocalization.string("失败")
        }
    }
    private func reconcileSelection() {
        let ids = Set(visible.map(\.id))
        selectedIDs.formIntersection(ids)
        if !ids.contains(selectedPhotoID ?? UUID()) { selectedPhotoID = visible.first?.id }
        if !multiSelect { selectedIDs = selectedPhotoID.map { [$0] } ?? [] }
    }
    private func status(_ photo: WatermarkCapturedPhoto) -> String {
        let saved = photo.isPersisted ? AppLocalization.string("已暂存") : AppLocalization.string("暂存失败，请重试")
        let album = photo.albumStatus == .completed ? AppLocalization.string("已存相册")
            : (photo.albumAttemptID != nil ? AppLocalization.string("相册结果待核对") : AppLocalization.string("待存相册"))
        let archive = photo.archiveStatus == .completed ? AppLocalization.string("已归档") : AppLocalization.string("待归档")
        return [saved, album, archive].joined(separator: " · ")
    }
}

private struct WatermarkDraftZoomView: View {
    let photo: WatermarkCapturedPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            WatermarkDraftImageView(photo: photo, maxPixelSize: 2400)
                .scaleEffect(scale).offset(offset)
                .gesture(MagnifyGesture().onChanged { value in scale = min(5, max(1, settledScale * value.magnification)) }
                    .onEnded { _ in settledScale = scale; if scale == 1 { offset = .zero; settledOffset = .zero } })
                .simultaneousGesture(DragGesture().onChanged { value in
                    guard scale > 1 else { return }
                    offset = CGSize(width: settledOffset.width + value.translation.width, height: settledOffset.height + value.translation.height)
                }.onEnded { _ in settledOffset = offset })
                .accessibilityLabel(AppLocalization.string("照片大图，使用手势缩放和移动"))
            Button(AppLocalization.string("关闭")) {
                dismiss()
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2), in: Capsule())
            .safeAreaPadding(.top)
            .padding(.trailing, 16)
        }
    }
}

/// Loads a bounded image off the main thread and discards work when the view changes.
struct WatermarkDraftImageView: View {
    let photo: WatermarkCapturedPhoto
    var maxPixelSize: Int = 720
    @State private var image: UIImage?
    @State private var finished = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Rectangle().fill(.secondary.opacity(0.12)).overlay {
                    if finished { Image(systemName: "photo.badge.exclamationmark").accessibilityLabel(AppLocalization.string("照片加载失败")) }
                    else { ProgressView() }
                }
            }
        }
        .task(id: "\(photo.id)-\(photo.watermarkedURL?.path ?? "pending")-\(maxPixelSize)") {
            image = nil
            finished = false
            let loaded = await WatermarkCameraImageLoader.shared.thumbnail(for: photo, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
            finished = true
        }
        .onDisappear {
            image = nil
            finished = false
        }
    }
}
