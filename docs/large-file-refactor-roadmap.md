# Large File Refactor Roadmap

This roadmap tracks staged decomposition of oversized source files to reduce merge conflicts, improve testability, and keep future feature work maintainable.

## Scope

- Sources/Features/项目/ProjectFileBrowserView.swift (442) [Completed]
- Sources/Shared/Services/ReportBuilder.swift (1292)
- Sources/Features/项目/ProjectDetailView.swift (1105)
- Sources/Shared/Models/CommonMaterial.swift (1058)
- Sources/Features/项目/DailyLogView.swift (1010)

## Guiding Rules

- No behavior changes during extraction-only steps.
- Keep each PR focused on one file family.
- Move code first, then rename/refine in follow-up PRs.
- Add or update tests before changing logic.

## Phase 1: ProjectFileBrowserView

Status: Completed. The file is now 442 lines and no longer a large-file blocker.

Target split:
- ProjectFileBrowserRootView.swift: root list and search shell.
- ProjectFileCategoryScene.swift: project category page and recent files section.
- ProjectFileItemComponents.swift: row/chip/thumb and guide strip components.
- ProjectFileCollector.swift: keep data assembly logic separate from view rendering.

Done criteria:
- File size under 500 lines for each new view file.
- Existing file browsing flow unchanged.

## Phase 2: ReportBuilder

Target split:
- ReportBuilder+CSV.swift
- ReportBuilder+PDF.swift
- ReportBuilder+Excel.swift
- ReportBuilder+Formatting.swift

Done criteria:
- Public API of ReportBuilder remains stable.
- Export tests pass with baseline snapshots.

## Phase 3: ProjectDetailView

Target split:
- ProjectDetailHeaderSection.swift
- ProjectDetailQuickActions.swift
- ProjectDetailContainers.swift
- Keep navigation/routing coordination in ProjectDetailView.swift only.

Done criteria:
- Main ProjectDetailView file below 450 lines.
- Existing routing tests continue to pass.

## Phase 4: CommonMaterial

Target split:
- CommonMaterialCatalog.swift: static preset data only.
- CommonMaterialTags.swift: tag/category constants.
- CommonMaterialSearchIndex.swift: optional search helper/indexing.

Done criteria:
- Data updates do not require touching logic code.
- Material suggestion behavior unchanged.

## Phase 5: DailyLogView

Target split:
- DailyLogListScene.swift
- DailyLogCalendarScene.swift
- DailyLogComposerSheet.swift
- DailyLogAttachmentComponents.swift

Done criteria:
- Main DailyLogView below 450 lines.
- Daily log unit/UI tests remain green.

## Suggested PR Order

1. ReportBuilder split
2. DailyLogView split
3. ProjectDetailView split
4. CommonMaterial data split

## Verification Checklist Per PR

- xcodebuild -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -destination 'id=<SIMULATOR_UDID>' build
- xcodebuild test -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -destination 'id=<SIMULATOR_UDID>'
- If UI touched: xcodebuild test -project sitekeeper.xcodeproj -scheme sitekeeper-iOS-UITests -destination 'id=<SIMULATOR_UDID>'
