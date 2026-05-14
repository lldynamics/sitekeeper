# DWG 回归样本库

这个目录用于沉淀 CAD 看图的真实 DWG 回归样本，重点覆盖“不同 DWG 版本、图块、文字编码、字体、外部参照和代理对象”。

## 目录

- `manifest.json`：样本清单、覆盖标签和预期结果。
- `samples/`：真实 DWG 文件，本地保留，不提交。
- `reports/`：本地回归运行报告，不提交。
- `reports/latest.json`：建议保留最近一次完整结果，里面包含解析耗时、XREF 本地解析和文字诊断快照。

## 添加样本

1. 把 DWG 放入 `samples/` 下的分类目录。
2. 在 `manifest.json` 新增或更新条目。
3. 把条目的 `status` 改为 `ready`。
4. 运行：

```sh
python3 scripts/cad/dwg_regression.py
```

## 状态约定

- `needed`：计划需要，但还没收集到真实文件。
- `ready`：文件已经放入 `samples/`，应纳入回归校验。
- `blocked`：暂时不能收集或不能公开保存，只保留需求记录。

## 覆盖重点

- 版本：R12、R13、R14、2000、2004、2007、2010、2013、2018、2026+。
- 图块：`INSERT`、`MINSERT`、嵌套块、匿名块、动态块、属性文字、`BYBLOCK/BYLAYER`、基点。
- 文字：GBK、BigFont、SHX、字体缺失、乱码修复。
- 对象：HATCH、DIMENSION、LEADER、SPLINE、ELLIPSE、IMAGE、WIPEOUT。
- 异常：XREF 缺失、AEC/天正/PROXY、超大对象数、损坏 DWG。

## 文字诊断

`dwg_regression.py` 会从 ready 样本中抽取最多 80 条 TEXT/MTEXT/DIMENSION 文本，优先保留 BigFont、SHX、AutoCAD 控制码和疑似乱码样本。报告里的 `textDiagnostics` 用来判断乱码来源：

- `latin1-mojibake`：像 GBK/GB18030 字节被当成 Latin-1/Win1252。
- `halfwidth-katakana-mojibake`：中文字节被当成日文/CP932 一类编码，常见表现是大量半角片假名。
- `unexpanded-autocad-escape`：`\U+XXXX` 或 `\M+...` 没有展开。
- `unexpanded-mtext-control`：`\P`、`\A`、`\C` 等 MTEXT 控制符还没被渲染层归一化。
- `unexpanded-cad-control-code`：`%%c`、`%%d`、`%%p` 这类 CAD 控制码还没归一化。
- `question-mark-loss` / `replacement-character`：上游可能已经丢字节，Swift 字体 fallback 无法恢复。
- `mixed-symbol-mojibake` / `control-character`：解码结果混入半角符号、制表外控制字符或绘图符号，通常要回到原始字节和 codepage 判断。
- `non-gbk-fallback-decode`：中文项目里被判到 CP932/CP949/Big5 等兜底编码，需要重点复查。
- `bigfont-needs-verification`：样式带大字体且原始字节包含高位字节，但未命中更明确的乱码类型，需要人工确认。
