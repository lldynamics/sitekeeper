import SwiftUI

struct CADDrawingBrowser<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

extension CADPreviewContainer {
    var drawingTabStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button {
                    showDrawingTreeSheet = true
                } label: {
                    Label(drawingPositionText, systemImage: "folder")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button {
                    switchDrawingByOffset(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .disabled(!canSwitchDrawingByOffset(-1))
                .accessibilityLabel(String(localized: "上一张图纸"))

                Button {
                    switchDrawingByOffset(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .disabled(!canSwitchDrawingByOffset(1))
                .accessibilityLabel(String(localized: "下一张图纸"))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentDrawingTabs) { drawing in
                        drawingTabButton(for: drawing)
                    }

                    if recentDrawingTabs.count < projectDrawingTabs.count {
                        Button {
                            showDrawingTreeSheet = true
                        } label: {
                            Label(String(localized: "全部目录"), systemImage: "list.bullet.indent")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    func drawingTabButton(for drawing: ProjectDrawing) -> some View {
        let isActive = drawing.id == activeRequest.drawingID
        return Button {
            switchToDrawing(drawing)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ProjectDetailDrawingHelper.drawingIcon(drawing.fileType))
                Text(drawing.name.isEmpty ? drawing.fileName : drawing.name)
                    .lineLimit(1)
                Text(drawing.version)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isActive ? .white.opacity(0.8) : .secondary)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? .white : .primary)
            .background(
                Capsule()
                    .fill(isActive ? Color.appPrimaryAction : Color(uiColor: .tertiarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换图纸 \(drawing.name.isEmpty ? drawing.fileName : drawing.name)")
    }

    var drawingTreeSheet: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "搜索图纸名称、版本、目录"), text: $drawingTreeSearchText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        if !drawingTreeSearchText.isEmpty {
                            Button {
                                drawingTreeSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "清空图纸搜索"))
                        }
                    }
                }

                Section {
                    if drawingTreeGroups.isEmpty {
                        ContentUnavailableView(
                            String(localized: "暂无图纸"),
                            systemImage: "folder",
                            description: Text(String(localized: "导入 ZIP 图纸包或项目图纸后会显示目录。"))
                        )
                    } else if filteredDrawingTreeGroups.isEmpty {
                        ContentUnavailableView(
                            String(localized: "没有匹配图纸"),
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(String(localized: "换个名称、版本或目录关键词继续搜索。"))
                        )
                    } else {
                        ForEach(filteredDrawingTreeGroups) { group in
                            DisclosureGroup {
                                ForEach(group.drawings) { drawing in
                                    Button {
                                        showDrawingTreeSheet = false
                                        switchToDrawing(drawing)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: ProjectDetailDrawingHelper.drawingIcon(drawing.fileType))
                                                .foregroundStyle(Color.appDoc)
                                                .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(drawing.name.isEmpty ? drawing.fileName : drawing.name)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text("\(drawing.version) · \(drawing.fileType.uppercased())")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                            if drawing.id == activeRequest.drawingID {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.appSuccess)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label("\(group.title) · \(group.drawings.count) 张", systemImage: "folder")
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "图纸包目录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "完成")) {
                        drawingTreeSearchText = ""
                        showDrawingTreeSheet = false
                    }
                }
            }
        }
    }

    func drawingTreeSearchFields(for drawing: ProjectDrawing, groupTitle: String) -> [String] {
        [
            groupTitle,
            drawing.name,
            drawing.fileName,
            drawing.version,
            drawing.fileType,
            drawing.note,
            ProjectDetailDrawingHelper.zipEntryPath(for: drawing) ?? "",
            ProjectDetailDrawingHelper.zipFolderPath(for: drawing) ?? ""
        ]
    }

    func preferredDrawingTabSort(_ lhs: ProjectDrawing, _ rhs: ProjectDrawing) -> Bool {
        if lhs.isCurrentVersion != rhs.isCurrentVersion {
            return lhs.isCurrentVersion && !rhs.isCurrentVersion
        }
        let leftDate = Formatters.parseDateOrDateTime(lhs.importedAt) ?? .distantPast
        let rightDate = Formatters.parseDateOrDateTime(rhs.importedAt) ?? .distantPast
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        return (lhs.name.isEmpty ? lhs.fileName : lhs.name)
            .localizedStandardCompare(rhs.name.isEmpty ? rhs.fileName : rhs.name) == .orderedAscending
    }

    func switchToDrawing(_ drawing: ProjectDrawing) {
        guard drawing.id != activeRequest.drawingID else { return }
        persistSnapshotIfNeeded(snapshot)
        nativeCanvasTransform = nil
        nativeSnapPoints.removeAll()
        nativeEndpointSnapPoints.removeAll()
        nativeMidpointSnapPoints.removeAll()
        nativeCenterSnapPoints.removeAll()
        nativeSnapSourcePoints.removeAll()
        tool = .browse

        switch ProjectDetailAssetActions.previewDrawingURL(for: drawing) {
        case .success(let url):
            let nextRequest = previewRequest(for: drawing, fileURL: url)
            activeRequest = nextRequest
            selectedTextEncoding = nextRequest.textEncoding
            selectedTextBigFont = nextRequest.textBigFont
            textSchemeSnapshot = nextRequest.textSchemeSnapshot
            snapshot = restoredSnapshot(for: nextRequest)
            touchRecentDrawingTab(nextRequest.drawingID)
            quantityHighlightTarget = nil
            snapshot.normalizeMeasurementScale()
            applyOverlayDisplayPreferences(from: snapshot)
            lastPersistedSnapshotData = encodedSnapshotData(snapshot)
            clearInProgress()
        case .failure(let message):
            StorageIssueLog.record("CAD 图纸切换失败：\(drawing.name.isEmpty ? drawing.fileName : drawing.name)，\(message)")
        }
    }

    func canSwitchDrawingByOffset(_ offset: Int) -> Bool {
        guard offset != 0,
              let index = activeRecentDrawingIndex else { return false }
        let nextIndex = index + offset
        return recentDrawingTabs.indices.contains(nextIndex)
    }

    func switchDrawingByOffset(_ offset: Int) {
        guard canSwitchDrawingByOffset(offset),
              let index = activeRecentDrawingIndex else { return }
        switchToDrawing(recentDrawingTabs[index + offset])
    }

    func loadRecentDrawingTabs() {
        guard let raw = UserDefaults.standard.data(forKey: recentDrawingTabsStorageKey) else {
            recentDrawingTabIDs.removeAll()
            return
        }
        do {
            recentDrawingTabIDs = try JSONDecoder().decode([UUID].self, from: raw)
        } catch {
            recentDrawingTabIDs.removeAll()
            UserDefaults.standard.removeObject(forKey: recentDrawingTabsStorageKey)
            StorageIssueLog.record("CAD 最近图纸页签解析失败：\(activeRequest.projectId.uuidString)，\(error.localizedDescription)")
        }
        pruneRecentDrawingTabs()
    }

    func persistRecentDrawingTabs() {
        do {
            let data = try JSONEncoder().encode(recentDrawingTabIDs)
            UserDefaults.standard.set(data, forKey: recentDrawingTabsStorageKey)
        } catch {
            StorageIssueLog.record("CAD 最近图纸页签保存失败：\(activeRequest.projectId.uuidString)，\(error.localizedDescription)")
        }
    }

    func pruneRecentDrawingTabs() {
        let validIDs = Set(projectDrawingTabs.map(\.id))
        let filtered = recentDrawingTabIDs.filter { validIDs.contains($0) }
        if filtered != recentDrawingTabIDs {
            recentDrawingTabIDs = filtered
            persistRecentDrawingTabs()
        }
    }

    func touchRecentDrawingTab(_ drawingID: UUID) {
        recentDrawingTabIDs.removeAll { $0 == drawingID }
        recentDrawingTabIDs.insert(drawingID, at: 0)
        if recentDrawingTabIDs.count > 5 {
            recentDrawingTabIDs = Array(recentDrawingTabIDs.prefix(5))
        }
        persistRecentDrawingTabs()
    }
}
