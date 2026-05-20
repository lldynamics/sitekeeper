# 工地掌柜 Release Checklist

## 0. 版本与代码冻结
- [ ] 确认 `project.yml` 中 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 已递增
- [ ] 运行 `xcodegen generate`，确认 `project.yml` 与 `sitekeeper.xcodeproj` 同步
- [ ] 确认 `xcodegen generate` 后 `git diff -- sitekeeper.xcodeproj project.yml` 为空（无工程漂移）
- [ ] 清理并确认本次发布的提交范围（无临时调试代码）
- [ ] 工作区必须干净（`git status --short` 为空）；如需跳过，记录原因
- [ ] 清理仓库垃圾文件（如 `.DS_Store`），确保预检不拦截
- [ ] 本地已启用提交前守卫（一次性）：`scripts/dev/install_git_hooks.sh`
- [ ] 运行一键预检：`scripts/release/preflight.sh`

## 1. 构建验证
- [ ] Debug 构建通过：`xcodebuild -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] Release 构建通过：`xcodebuild -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] Widget Extension 构建通过（由主 Target 联编）

## 2. 自动化测试
- [ ] 单元测试通过：`xcodebuild test -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -destination 'id=<SIMULATOR_ID>' CODE_SIGNING_ALLOWED=NO`
- [ ] UI 测试通过：`xcodebuild test -project sitekeeper.xcodeproj -scheme sitekeeper-iOS-UITests -destination 'id=<SIMULATOR_ID>' CODE_SIGNING_ALLOWED=NO`
- [ ] 若执行预检脚本，确认 `scripts/release/preflight.sh` 输出 `Release preflight passed`

## 3. 核心业务回归
- [ ] 项目/工作台/工具箱/随手记/我的 首页可进入
- [ ] iPad 分栏：进入三级详情后切换左侧一级模块，右侧能正确刷新
- [ ] 材料单/报价/记账/施工工艺库新增与编辑正常
- [ ] 项目导出、备份导出、备份导入完整可用

## 4. 备份与恢复
- [ ] 本地 ZIP 导出成功，且可导入恢复
- [ ] iCloud 手动备份可上传、可列出、可恢复
- [ ] 自动备份策略（含 Wi-Fi 选项）按预期工作
- [ ] 缺失附件提示、二次确认流程正常

## 5. Widget 校验
- [ ] 小组件显示数据与 App 内一致
- [ ] `进行中` 与 `暂停` 项目都会被统计为活跃项目
- [ ] 修改关键数据后，小组件时间线能刷新

## 6. 权限与隐私
- [ ] 相机/相册/定位/麦克风权限弹窗文案正确
- [ ] `PrivacyInfo.xcprivacy` 与 App Store Connect 隐私标签一致
- [ ] App 内隐私政策文案与实际行为一致（反馈邮件、iCloud 备份、本地存储）

## 7. 上架物料
- [ ] App 图标槽位无过时告警
- [ ] 截图与应用版本一致（手机 + 平板）
- [ ] 版本更新说明完成
- [ ] 更新说明避免夸大 CAD 能力（表述为“系统 CAD 预览 + 批注/测量/半自动算量”）
- [ ] 更新说明包含提示：“电工计算、测量、算量结果用于辅助估算，现场以规范和专业判断为准”

## 8. 发布后留档
- [ ] 记录本次版本号、构建号、测试结果与已知风险
- [ ] 对应 Git tag 已创建并推送

## 9. 预检脚本参数
- `scripts/release/preflight.sh`: 默认执行 `xcodegen + Debug/Release build + unit/UI tests`
- 预检脚本会在 `xcodegen` 后校验工程漂移，并在工作区脏时输出前 80 条变更明细
- 预检脚本默认自动选择可用 iPhone 模拟器；如需指定可传入环境变量 `SIM_ID=<SIMULATOR_ID>`
- `scripts/release/preflight.sh --skip-tests`: 仅跑构建与工程同步检查
- `scripts/release/preflight.sh --allow-dirty`: 允许工作区非干净（仅用于紧急场景，需留档）
