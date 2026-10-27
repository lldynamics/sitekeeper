# 单位换算主机验证

在项目根目录运行：

```sh
python3 scripts/tests/run_unit_conversion_host_tests.py
```

入口只编译两份完整生产源文件：`EngineeringCalculations.swift`、`CalculationValidator.swift`。
不裁剪、不复制算法，不需要模拟器或第三方依赖。使用正常 SwiftPM 沙箱，失败后停止，不自动换入口重试。

共 9 项测试：直接复用 `Tests/UnitConverterTests.swift` 的原 5 项，新增 4 项对应
`Tests/CalculationCoreTests.swift` 中的单位换算契约。原测试、UI、CI 和发布门禁均保留。

| 原测试 | 主机断言 |
| --- | --- |
| `meterToFeet` | 1 米 → 3.28084 英尺，误差严格小于 0.001 |
| `feetToMeter` | 1 英尺 → 0.3048 米，误差严格小于 0.001 |
| `muToSquareMeter` | 1 亩 → 666.667 平方米，误差严格小于 0.01 |
| `tonToKg` | 1 吨 → 1000 千克，误差严格小于 0.001 |
| `zeroValue` | 零值严格等于 0 |
| `unitConvertBasic` | 两个方向的 1000 倍换算均严格相等 |
| `unitConvertZero` | 原系数 100、目标系数 10 的零输入严格等于 0 |
| `unitConvertInvalidFactor` | 目标系数为 0 时，旧接口返回 0 |
| `unitConvertValidatedRejectsInvalidFactor` | 精确匹配目标单位系数的 `mustBeGreaterThanZero` 错误 |

每次新建 `build/unit-conversion-host/` 下的证据目录，不清理或覆盖已有目录。
先用本次全新的构建与模块缓存运行一次，再以相同路径运行一次；保存日志、输入 SHA-256、
测试数量和完整命令墙钟耗时。这里的“冷”仅指本次任务缓存全新，系统及 SDK 缓存可能已有内容。
结果不代表 iOS 集成、UI、其他工程公式或 Duo 验收通过，也不用于宣称固定提速倍数。
