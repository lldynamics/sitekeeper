# DWG 样本目录

这里放真实 DWG 回归样本。目录已被 `.gitignore` 忽略，避免把项目图纸或客户图纸误提交。

建议命名：

- `versions/ac1009-r12-basic-2d.dwg`
- `blocks/ac1032-nested-insert-base-point.dwg`
- `blocks/ac1032-minsert-attributes-byblock.dwg`
- `text/ac1027-gbk-bigfont-shx.dwg`
- `xref/ac1032-xref-host.dwg`
- `xref/xref/ac1032-xref-child.dwg`
- `xref/参照/ac1032-xref-child-cn.dwg`

放入文件后，把 `Regression/DWG/manifest.json` 中对应条目的 `status` 改为 `ready`，再运行：

```sh
python3 scripts/cad/dwg_regression.py
```
