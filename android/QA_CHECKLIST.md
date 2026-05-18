# Android QA Checklist

Use this checklist before treating the Android port as a usable test build.

## Build And Install

- Build: `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH" ./gradlew :core:model:test :app:testDebugUnitTest :app:assembleDebug --no-daemon`
- Install and launch: `./scripts/check_debug_install.sh`
- If more than one device is connected: `ANDROID_SERIAL=<device-id> ./scripts/check_debug_install.sh`

## Smoke Flow

- Launch app and confirm the first screen loads without a crash.
- Open `首页`, confirm risk summary and recent project shortcuts render.
- Open `项目`, enter a seeded project, then return to the project list.
- Create, edit, archive, restore, and delete a local project.
- Open `计算`, switch between 混凝土、墙面、地砖、电流、压降、换算, and confirm results update after changing inputs.
- Open `材料库`, search/filter by category, add/edit/delete one material price, add/edit/delete one supplier, and confirm the price row can show linked supplier details.
- Open `工艺库`, filter by 专业/状态, add/edit/delete one construction method, and confirm 工序、质检、安全清单 render in the row.
- In a project, add/edit one 日志, 待办, and 项目资料 with a linked 工艺库 item, then confirm the rows display `关联工艺`.
- In a project, confirm `项目时间线` appears below the project metrics and combines 日志、待办、进度、收支、材料、资料、图纸、报价、用工、仓库流水 by latest date.
- In a project, confirm `项目交付` shows actual packaged file counts plus missing-file details, then tap `导出交付包`, save the ZIP with the Android document picker, and confirm it contains `交付报告.md`, `文件清单.md`, archived project documents, drawings, and site photos.
- Add and edit施工日志, 待办, 进度, 联系人, 项目资料, 项目图纸, 报价, 用工, and 仓库流水 records.

## Local Files

- Project document: pick a file, confirm status becomes archived, open it, then remove/delete the record.
- Drawing: pick a PDF/image/DWG-style file, open it, then delete the drawing and confirm the local archive is removed.
- Daily log photo: add a photo, open it, remove it.
- Todo before/after photo: add both photos, open them, remove them.
- Quick note attachment: add photo/audio/video/PDF-style files, search by attachment name, open each attachment, remove it.

## Backup Package

- Export a ZIP package from `我的`.
- Confirm export status reports document, photo, drawing, quick note attachment, material price, supplier, and construction method counts.
- Import the ZIP as merge and confirm records remain usable.
- Import the ZIP as replace and confirm archived local files still open.
- Import legacy JSON and confirm file-related warnings are shown for metadata-only attachments.
- Import a deliberately incomplete ZIP and confirm preflight warnings identify missing or orphaned files.
- Open `我的`, confirm `数据体检` shows missing/orphan counts for documents, photos, drawings, and quick note attachments, then run `重新体检`; if missing originals exist, confirm `缺失明细` lists the affected items, `打开项目` jumps to the correct project, and `生成整改待办` creates project todo rows without duplicates.

## Release Gate

- Debug build passes.
- APK installs and launches on at least one physical Android phone.
- File picker works on Android 13+ without broad storage permissions.
- Backup ZIP can round-trip data and local files.
- No crash during project detail scrolling with seeded data.
