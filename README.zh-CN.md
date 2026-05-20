# 工地掌柜（iOS / iPadOS）

一个基于 SwiftUI 的工地工具箱，用来做现场计算、材料/人工记录、报价、施工日志、进度跟踪、备份和导出。

系统要求：iOS 17.0+ / iPadOS 17.0+（依赖 Swift Observation）。

## 当前功能

- 首页：快捷入口、待补材料提醒、近期项目记录。
- 计算：电流、电缆压降和线径推荐、线管穿线率、桥架填充率、空开/漏保选型、混凝土算量、钢筋重量、地砖排料、墙面面积、单位换算。
- 清单：材料清单、人工记录、报价单、自定义材料库，并支持关联项目。
- 项目：工程列表、经营看板、项目详情概览、施工进度任务、历史计算、增强施工日志。
- 施工日志：列表/日历视图、项目/日期/搜索筛选、安全记录、材料记录、天气记录、多张照片和照片备注。
- 导出/备份：CSV、PDF、Excel 兼容 HTML、报价单 PDF、完整 ZIP 原文件备份（含数据索引 + 照片/图纸/资料/随手记与工艺附件）、合并/覆盖导入、iCloud 备份与恢复预览、ZIP64 大包流式导出。
- 数据健康：支持一键检查缺失原件、孤立项目关联和异常引用，并提供修复入口。
- 小组件：按风险优先展示项目（逾期/待办优先）、待办与库存摘要，并显示最近同步时间。
- 发布基础：应用图标、隐私清单、正式 Bundle ID、版本号/构建号、共享测试 scheme、单元测试。

## 快速启动

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

启用本地提交前守卫（一次性）：

```sh
scripts/dev/install_git_hooks.sh
```

## 目录结构

- `Sources/App`：应用入口和底部导航。
- `Sources/Features`：按功能页签拆分的业务界面。
- `Sources/Shared`：公共模型、服务、计算辅助和通用组件。
- `Sources/Resources`：应用资源、隐私清单和图标资源。
- `Tests`：单位换算、报价、备份兼容、筛选删除、工程推荐等单元测试。

## 扩展新功能

- 新增计算器：在 `Sources/Features/计算` 新建视图，并在 `CalculatorTabView.calcDefs` 注册入口。
- 新增持久化数据：在 `DataStore.swift` 增加模型字段，并同步考虑备份、导出和删除项目时的清理逻辑。
- 新增工程公式：优先放到 `EngineeringCalculations.swift`，再补对应单元测试。
