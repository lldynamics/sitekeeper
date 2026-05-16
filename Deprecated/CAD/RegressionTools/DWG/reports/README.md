# DWG 回归报告

这里放本地生成的回归报告，默认不提交。

建议输出文件：

- `reports/latest.json`
- `reports/latest.md`

`latest.json` 中每个 ready 样本的 `parser.textDiagnostics` 会记录文字抽样、可疑类型、codepage 分布和 STYLE/font/bigfont 提示。排查乱码时优先看 `issueSamples`，不要先从 UI 字体猜。
