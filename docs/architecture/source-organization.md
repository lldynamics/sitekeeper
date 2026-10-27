# 工程结构与接入规范

业务源码使用英文 ASCII 路径。中文标题和文案保留在本地化资源与 UI 中。`project.yml` 是 Xcode 工程的生成源；目录调整后运行 `xcodegen generate`，同时更新脚本、源码路径测试、SwiftLint baseline 中的路径和 Widget 单独编译的共享文件引用。

## 领域目录

| 位置 | 职责 |
| --- | --- |
| `Features/Projects/Catalog`、`Detail` | 项目列表、创建编辑、详情装配及路由 |
| `Features/Projects/DailyLogs`、`Todos`、`Progress` | 日志、待办、进度 |
| `Features/Projects/Finances`、`Warehouse` | 项目财务、往来与仓储 |
| `Features/Projects/Documents`、`Drawings`、`Files`、`Delivery` | 资料、图纸、文件浏览、交付导出 |
| `Features/Projects/Contacts`、`ConstructionMethods`、`Repository` | 联系人、工艺关联、数据库候选工作台 |
| `Features/Checklists` | 工具箱入口，以及材料、报价、人工、图纸台账、工艺和水印相机子域 |
| `Features/Calculators` | 计算器视图与唯一入口注册表 `CalculatorDestination` |
| `Features/Dashboard`、`QuickNotes` | 首页和随手记 |
| `Features/Profile` | 备份、数据健康、管理、清理、设置和身份资料子域 |
| `Shared/Models` | 共享领域值类型 |
| `Shared/Services/Persistence` | DataStore 生命周期、领域写入口及领域存储 |
| `Shared/Services/Repository` | SQLite 候选模型、分页查询和适配层 |
| `Shared/Services/Backups`、`Archiving`、`Storage` | 备份协议与恢复事务、ZIP 适配、原文件存储 |
| `Shared/Services/Reporting`、`Search`、`Notifications`、`Widgets` | 报表、检索、提醒、小组件数据契约 |

这里的领域目录仍在同一个应用模块中。目录归组本身不会建立 Swift 模块级依赖隔离；跨域写入继续通过 DataStore 明确的写入口完成。

## 文件拆分

先按业务归属放置，再按稳定职责拆分。一个类型的扩展与主类型放在同一子域；新文件应能用业务职责解释，而不只是为了减少主文件行数。小型、同职责的扩展可合并，独立的持久化、照片导入或复杂表单继续分开。不要为了消除行数告警把状态暴露给整个模块，也不要合并成另一个超大文件。已有 SwiftLint debt 仅迁移路径，不重新生成 baseline 来隐藏新问题。

本次把 DailyLog 的筛选与日期辅助合并到 `+Queries`，编辑与删除合并到 `+Editing`，照片操作与照片墙合并到 `+Photos`，展示包装合并到 `+Layout`。草稿恢复、表单、状态模型仍有独立职责。

## 新计算器

1. 在 `Features/Calculators` 添加视图；可复用公式放在 `Shared/Helpers/EngineeringCalculations.swift`。
2. 在 `CalculatorDestination.swift` 添加枚举项、图标、标题、说明、分组和目标视图。
3. `Checklists/Toolbox/QuickToolViews.swift` 自动枚举该注册表；只有增加工具箱顶级类别时才需要修改 `ToolboxCatalog`。
4. 公式和输入边界加入现有计算测试，确认工具箱列表与搜索均可到达。

## ZIP 依赖与备份契约

ZIPFoundation 固定为 0.9.20，解析提交由 `Package.resolved` 固定。ZIP/ZIP64 的条目头、目录头、时间编码、压缩及 CRC 计算由库处理。应用仅保留 `StreamingZipArchiveWriter`、`SimpleZipArchiveReader` 的兼容接口和应用级限制。旧手写 ZIP 生成器位于 `Tests/Support`，仅供历史格式及畸形包测试，不参与 App target。

适配层继续拒绝绝对路径、反斜线、空路径段、`.`、`..`、NUL、冒号、重复路径及符号链接；解压使用受限分块 consumer，并核对实际大小和 CRC。临时输出只有通过校验后才替换目标文件，失败和取消清理临时文件。ZIPFoundation 的迭代器遇到坏条目会提前结束，因此 `ZipArchiveEnvelope` 只读取结束记录中的数量并要求完整枚举；它不实现条目解码或解压引擎。

备份 schema、manifest、文件路径和恢复事务不因库替换而升级。历史固定 ZIP、标准解压软件互通、ZIP64、压缩包、CRC、重复路径、畸形索引和容量限制都需要回归。目录迁移与本地构建不能替代真机、iCloud 或发布验收。

## 可移植发布检查

`check_*policy.sh` 与备份/图纸边界守卫共用 `scripts/lib/policy_search.sh`，统一使用 POSIX ERE。优先使用 `rg`，缺失时使用系统 `find` 与 `grep -E`；`SITEKEEPER_SEARCH_BACKEND=grep` 可强制验证降级路径。固定字符串检查使用 `grep -F`。搜索错误应导致守卫失败，不能被当成“未发现违规”。SwiftLint、SwiftFormat 和 XcodeGen 仍是各自构建检查的显式工具依赖。

本地化检查中的 Unicode Han 属性无法由 POSIX grep 表达；该部分降级使用 macOS 自带 Perl，普通边界守卫仍使用 grep。预检无需安装 ripgrep。

无需启动模拟器的专项验证：

```sh
bash scripts/tests/test_policy_search.sh
bash scripts/tests/test_zip_adapter.sh
SITEKEEPER_SEARCH_BACKEND=grep bash scripts/localization/check_localization_hardcoded_ui.sh --strict
```

ZIP 专项脚本把实际适配层、容量规则和测试复制到临时 SwiftPM 工程，替换本地化与文件操作日志的宿主接口，且不读取应用数据。macOS 专项还调用系统 `unzip -t` 检查输出互通性。已有固定版本源码时可通过 `SITEKEEPER_ZIPFOUNDATION_PATH` 指定离线 checkout，脚本会核对版本提交。
