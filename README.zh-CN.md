# 工地掌柜（iOS / iPadOS）

一个基于 SwiftUI 的工地工具箱，用来做现场计算、材料/人工记录、报价、施工日志、进度跟踪、备份和导出。

系统要求：iOS 17.0+ / iPadOS 17.0+。

[English](README.md) | 简体中文

本仓库公开供查看源代码，保留版权，未采用开源许可证。具体权限见
[COPYRIGHT.md](COPYRIGHT.md)，第三方组件许可见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 下载

在 iPhone 或 iPad 上通过 [App Store 香港区](https://apps.apple.com/hk/app/%E5%B7%A5%E5%9C%B0%E6%8E%8C%E6%9F%9C/id6766023111?uo=4)或[美国区](https://apps.apple.com/us/app/%E5%B7%A5%E5%9C%B0%E6%8E%8C%E6%9F%9C/id6766023111?uo=4)安装**工地掌柜**。需要 iOS 17.0 / iPadOS 17.0 或更高版本，无需注册或登录应用账号。

**地区说明（2026年10月30日）：**香港区和美国区已显示 1.0.4。中国大陆 App Store 当前暂不可下载，所需的 ICP 备案信息仍待补齐；能否下载以你的 Apple 账户所在地区的商店页面为准。

## 3步上手

1. **新建项目。**打开“项目 → 新建项目”，填写工程名称，按需补充其他资料，然后点“创建”。
2. **记下第一笔。**进入项目，点“新增记录 → 新增账目”记录收入或支出；材料和现场情况可分别通过“新增材料”或“写施工日志”保存。
3. **预览后分享。**从“更多操作 → 现场汇报与核对 → 施工日报与周报 → 预览正文 PDF”查看项目、日期和内容，再自行选择是否分享。

**保留备份：**进入“我的 → 数据管理 → 备份恢复”，在“本地备份”中选择“导出完整备份 ZIP”；iPad 也提供“生成本地备份 ZIP”快捷按钮。记录默认保存在本机，可选的 iCloud 功能用于同一 Apple ID 的备份与恢复，不是多人实时协作。

## 1.0.4更新摘要

- 改善工程收支、待收款及材料人工成本的展示，增加计算口径和待核对提示。
- 改善报价筛选、金额汇总及导出 PDF 中的金额说明。
- 改进 iPad 浮动键盘下的字段切换和表单取消操作。
- 改善 iPhone、iPad 待办与进度列表的筛选和位置保持。
- 修复 iPad 工程详情手动滚动后，再次选择“成本”未重新定位的问题。

完整发布说明见 [App Store 版本记录](https://apps.apple.com/hk/app/%E5%B7%A5%E5%9C%B0%E6%8E%8C%E6%9F%9C/id6766023111?uo=4)。下面的源码构建步骤面向开发者。

## 当前功能

- 首页：快捷入口、待补材料提醒、近期项目记录。
- 计算：电流、电缆压降和线径推荐、线管穿线率、桥架填充率、空开/漏保选型、混凝土算量、钢筋重量、地砖排料、墙面面积、单位换算。
- 清单：材料清单、人工记录、报价单、自定义材料库，并支持关联项目。
- 项目：工程列表、经营看板、项目详情概览、施工进度任务、历史计算、增强施工日志。
- 施工日志：列表/日历视图、项目/日期/搜索筛选、安全记录、材料记录、天气记录、多张照片和照片备注。
- 导出/备份：CSV、PDF、HTML 网页报表（.html）、报价单 PDF、完整 ZIP 原文件备份（含数据索引 + 照片/图纸/资料/随手记与工艺附件）、合并/覆盖导入、iCloud 备份与恢复预览、ZIP64 大包流式导出。
- 数据健康：支持一键检查缺失原件、孤立项目关联和异常引用，并提供修复入口。
- 小组件：按风险优先展示项目（逾期/待办优先）、待办与库存摘要，并显示最近同步时间。
- 发布基础：应用图标、隐私清单、正式 Bundle ID、版本号/构建号、共享测试 scheme、单元测试。

## 数据安全与确认流程

- 备份恢复使用持久化事务日志。若恢复中断，恢复包和日志会保留，应用可在下次读取时继续恢复；在读取和恢复完成前，清空数据、存储清理等维护操作会保持不可用。本机与云端导出还会在归档读取期间阻止清理和恢复。
- 只有备份 ZIP 和校验文件都确认上传后，应用才会记录 iCloud 上传成功。保留策略可选择最近 3、5、10 或 20 份已确认上传的备份，刷新备份列表时按已确认上传状态清理超出数量的旧备份；等待同步或上传失败的文件会保留。这里说明的是应用内上传状态口径，设备上的 iCloud 可用性仍需以实际环境为准。
- 从材料记录生成报价时，必须明确选择“沿用材料单价（成本参考）”“统一设置对外报价”或“留空待补”。把报价写入工程合同前会预览所选的已确认报价版本和写入金额；若源报价发生变化，预览会刷新并要求再次确认。
- 无法可靠判断计量单位的历史人工记录会标记为“待确认单位”，不会自动把数值解释成工时或工天。记录需编辑或批量确认单位后才能进入报价；确认单位不会换算原有数量和金额。

## 从源码构建（开发者）

1. 确保 Xcode 路径正确（只需执行一次）

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

2. 生成工程

   ```sh
   xcodegen generate
   ```

3. 打开工程

   ```sh
   open sitekeeper.xcodeproj
   ```

4. 在 Xcode 中选择 `sitekeeper-iOS` scheme，选 iPhone 或 iPad 模拟器运行。

## 一键脚本

```sh
bash bootstrap.sh
```

脚本会检查 `xcode-select`，并在需要时提示切换到完整 Xcode。

## 验证命令

先获取可用模拟器 UDID（测试必须指定具体设备）：

```sh
xcrun simctl list devices available
```

构建（仅编译 App）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -configuration Debug -destination 'id=<SIMULATOR_UDID>' build
```

单元测试：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -destination 'id=<SIMULATOR_UDID>'
```

UI 测试：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project sitekeeper.xcodeproj -scheme sitekeeper-iOS-UITests -destination 'id=<SIMULATOR_UDID>'
```

发布预检：

```sh
scripts/release/preflight.sh
```

App Store 签名归档预检：

```sh
scripts/release/archive_appstore.sh --dry-run
```

正式归档会先执行完整预检，然后生成签名 `.xcarchive`、IPA、签名权限快照和 SHA-256 证据文件：

```sh
scripts/release/archive_appstore.sh --allow-provisioning-updates
```

仅在明确需要上传 TestFlight 且已配置 App Store Connect API 密钥时使用：

```sh
ASC_KEY_PATH=/path/to/AuthKey.p8 \
ASC_KEY_ID=YOUR_KEY_ID \
ASC_ISSUER_ID=YOUR_ISSUER_ID \
scripts/release/archive_appstore.sh --allow-provisioning-updates --upload-testflight
```

归档产物默认位于 `build/AppStore/<版本-构建-时间>/`。脚本默认不会上传 TestFlight。

iPhone 与 iPad 自适应布局的发布级 UI 冒烟测试：

```sh
scripts/release/run_ui_smoke.sh --device-family iphone
scripts/release/run_ui_smoke.sh --device-family ipad
```

CI 会分别执行两种设备族，并保留对应的 `.xcresult` 作为失败证据。

安装与 CI 相同并经过 SHA-256 校验的固定工具版本（XcodeGen 2.46.0、SwiftFormat 0.61.1、SwiftLint 0.63.2），再执行 Swift 检查：

```sh
tools_dir="${TMPDIR:-/tmp}/sitekeeper-tools"
scripts/release/install_ci_tools.sh "$tools_dir"
export PATH="$tools_dir:$PATH"
scripts/dev/check_swift_format.sh
scripts/dev/check_swift_lint.sh
scripts/dev/format_swift.sh
```

启用本地提交前守卫（一次性）：

```sh
scripts/dev/install_git_hooks.sh
```

## 目录结构

- `Sources/App`：应用入口和底部导航。
- `Sources/Features`：英文功能目录 `Calculators`、`Checklists`、`Dashboard`、`QuickNotes`、`Profile`、`Projects`，内部继续按业务领域归组。
- `Sources/Shared/Models`：共享领域模型。
- `Sources/Shared/Services`：持久化、备份、归档、文件存储、报表、搜索等服务。
- `Sources/Shared/Helpers` 与 `Views`：公共辅助和通用组件。
- `Sources/Resources`：应用资源、隐私清单和图标资源。
- `Tests`：单位换算、报价、备份兼容、筛选删除、工程推荐等单元测试。

## 扩展新功能

- 新增计算器：在 `Sources/Features/Calculators` 新建视图，并在 `CalculatorDestination.swift` 中补充类型、元数据和目标视图。工具箱通过 `QuickToolViews.swift` 使用这一份注册表，无需单独增加计算器首页。
- 新增持久化数据：在 `DataStore.swift` 增加模型字段，并同步考虑备份、导出和删除项目时的清理逻辑。
- 新增工程公式：优先放到 `EngineeringCalculations.swift`，再补对应单元测试。

普通 Debug 构建跳过完整发布守卫；可设置 `SITEKEEPER_RUN_BUILD_GUARDS=1` 启用。Release 与发布预检会执行全部守卫，搜索优先使用 ripgrep，未安装时自动使用系统 `grep -E`。

领域归属、文件拆分和 ZIP 适配层约定见[工程结构与接入规范](docs/architecture/source-organization.md)。

## 源码与验证记录

私有测试报告、截图、结果包、备份及离线数据交付材料单独保留，不随仓库公开。
缺少某份报告不代表相应测试已通过，请按上面的验证命令核查所用源码版本。
公开前已清理历史中的旧 LibreDWG 依赖文件和私有验证记录，部分早期提交可能因此
无法独立构建。历史改写后应重新克隆仓库，避免旧副本把已清理的历史带回；
原始历史和测试证据由维护者私下保存。
