import SwiftUI

struct ChecklistTabView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("快捷工具") {
                    NavigationLink { WatermarkCameraToolView() } label: {
                        ToolRow(icon: "camera.aperture", title: "水印相机", desc: "独立拍照，导出带工程水印的现场图片", color: .blue)
                    }
                    NavigationLink { ProjectWarehouseOverviewView() } label: {
                        ToolRow(icon: "shippingbox.and.arrow.backward.fill", title: "项目仓库", desc: "查看所有项目材料库存和出入库流水", color: .brown)
                    }
                    NavigationLink { ProjectFileBrowserView() } label: {
                        ToolRow(icon: "folder.fill", title: "项目文件", desc: "按项目查看照片、图纸、票据与随手记附件", color: .indigo)
                    }
                    NavigationLink { QuickToolCategoryListView() } label: {
                        ToolRow(icon: "bolt.square.fill", title: "快捷工具", desc: "按电气、照明、土建、通用分类选择工具", color: .orange)
                    }
                }

                Section("经营与清单") {
                    NavigationLink { ProjectBusinessView() } label: {
                        ToolRow(icon: "chart.pie.fill", title: "经营看板", desc: "合同、收款、成本和利润概览", color: .orange)
                    }
                    NavigationLink { MaterialListView() } label: {
                        ToolRow(icon: "shippingbox.fill", title: "材料清单", desc: "材料数量、单价和采购状态", color: .brown)
                    }
                    NavigationLink { MaterialSheetView() } label: {
                        ToolRow(icon: "doc.richtext.fill", title: "材料单", desc: "从材料库选取或手动输入组建材料清单", color: .orange)
                    }
                    NavigationLink { QuotationView() } label: {
                        ToolRow(icon: "doc.text.fill", title: "报价明细", desc: "版本、状态和客户确认信息", color: .teal)
                    }
                    NavigationLink { LaborRecordView() } label: {
                        ToolRow(icon: "person.2.fill", title: "人工/辅材记录", desc: "工种、单价、金额和结算状态", color: .green)
                    }
                }

                Section("工程资料库") {
                    NavigationLink { MaterialPriceDatabaseView() } label: {
                        ToolRow(icon: "yensign.circle.fill", title: "材料价格库", desc: "材料、品牌、规格、供应商和参考价", color: .orange)
                    }
                    NavigationLink { SupplierDatabaseView() } label: {
                        ToolRow(icon: "person.2.badge.gearshape.fill", title: "供应商库", desc: "联系人、电话、供货范围和备注", color: .blue)
                    }
                    NavigationLink { ProjectContactDatabaseView() } label: {
                        ToolRow(icon: "person.crop.rectangle.stack.fill", title: "联系人", desc: "汇总所有项目联系人，按项目筛选", color: .cyan)
                    }
                    NavigationLink { ConstructionMethodLibraryView() } label: {
                        ToolRow(icon: "hammer.fill", title: "施工工艺库", desc: "标准做法、质量要求和安全注意", color: .green)
                    }
                    NavigationLink { QuotationTemplateLibraryView() } label: {
                        ToolRow(icon: "doc.text.fill", title: "报价模板库", desc: "常用报价项目和套价模板", color: .teal)
                    }
                    NavigationLink { MaterialLibraryView() } label: {
                        ToolRow(icon: "books.vertical.fill", title: "常用材料库", desc: "预置材料、规格和单位", color: .indigo)
                    }
                }

                Section("数据与模板") {
                    NavigationLink { ExportView() } label: {
                        ToolRow(icon: "square.and.arrow.up", title: "全局导出", desc: "按项目或时间范围导出 CSV / PDF / Excel", color: .indigo)
                    }
                    NavigationLink { TemplateView() } label: {
                        ToolRow(icon: "doc.text", title: "模板管理", desc: "常用日志、待办和项目模板（应用前先预览确认）", color: .purple)
                    }
                    NavigationLink { DataHealthView() } label: {
                        ToolRow(icon: "stethoscope", title: "数据健康检查", desc: "缺失文件和无效关联检查", color: .orange)
                    }
                }

                Section("查询") {
                    NavigationLink { GlobalSearchView() } label: {
                        ToolRow(icon: "magnifyingglass", title: "全局搜索", desc: "项目、联系人、票据、日志和随手记", color: .indigo)
                    }
                    NavigationLink { HistoryView() } label: {
                        ToolRow(icon: "clock.arrow.circlepath", title: "历史计算", desc: "计算过程和结果留存", color: .gray)
                    }
                }
            }
            .navigationTitle("工程数据库")
        }
    }
}
