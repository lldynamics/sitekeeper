# CAD Sample Corpus

`samples/cad/` 用于本地真实图纸回归测试。

规则：

- 真实 DWG 样本只放本机测试，不要提交到公开仓库。
- 真实项目图纸、带业主信息的图纸、外部参照文件都不要上传。
- 可以提交小型测试 fixture，例如中间 JSON、简单 DXF、mock CADDatabase。
- 已提交 fixture：
  - `intermediate/simple_floor_plan.json`：中间 JSON 黄金输入，覆盖 LINE/LWPOLYLINE/CIRCLE/ARC/TEXT/MTEXT/INSERT/ATTRIB/DIMENSION/HATCH。
  - `fixtures/simple_intermediate.json`：验证中间 JSON -> CADDatabase。
  - `fixtures/simple_site_plan.dxf`：验证简单 DXF -> CADDatabase -> Renderer，包含中文、MTEXT、控制码和基础图元。
  - `dxf/simple_floor_plan.dxf`：真实 2D DXF 解析样本，覆盖 TABLES/BLOCKS/ENTITIES 常见对象。
  - `dxf/nested_blocks_and_unsupported.dxf`：嵌套块 + unsupported 对象保留诊断样本。
- 真实样本建议按项目或问题类型分目录保存，方便和回归报告对应。

运行回归：

```sh
cad-regression samples/cad --output build/cad-regression
```

每张图纸输出：

- `diagnostics.json`
- `performance_trace.json`
- `text_trace.jsonl`
- `font_diagnostics.json`
- `unsupported_entities.json`
- `render_snapshot.png`，如果当前平台支持
- `summary.md`

总报告：

- `build/cad-regression/cad_regression_report.md`

上线验收目标：

- 30 张真实中文施工图中至少 27 张主要内容可显示。
- 中文乱码比例低于 1% 到 3%。
- 图纸不能白屏。
- 100MB 以下图纸二次打开要能较快进入可查看状态。
- 平移缩放不能明显卡死。
- 缺字体、缺 XREF、天正对象要有明确诊断。
