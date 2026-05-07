# 变更日志

## [1.0.1] — 优化与新增

### 新增
- 全局搜索索引自动刷新 — 数据变化后结果实时更新
- 材料单导出支持保存与分享选择
- 随手记导入文件/视频封装方法 — 修复干净安装首次导入失败

### 修复
- 项目删除级联不完整 — 随手记附件、待办整改照片不再遗留
- 后台保存 fire-and-forget — 生命周期切换时强制等待落盘
- 数据健康检查大文件内存压力 — 改用 exists 检查文件存在性
- iCloud 自动备份不在后台做重任务 — 仅在 active 时触发云备份

### 优化
- Enum rawValue 规范化 — 非 Codable 枚举改为英文 rawValue
- 测试断言模式改进 — 两步 assert 改为 #require
- NavigationLink 升级为新 API
- CalculatorTabView 消除 12 处 AnyView 类型擦除
