import Foundation

#if DEBUG
@MainActor
extension DataStore {
    func seedDefaults() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> String {
            let target = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return Formatters.date.string(from: target)
        }
        func dateTime(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> String {
            let base = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            let target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
            return Formatters.dateTime.string(from: target)
        }

        let projectsSeed: [Project] = [
            Project(name: "阳光花园 3# 楼", location: "城东区", status: .active, customerName: "宏远地产", customerPhone: "13800000001", startDate: day(-12), expectedEndDate: day(39), managerName: "李工", contractAmount: "118000", paidAmount: "42000", paymentStatus: .partial, materialCost: "36000", laborCost: "24000"),
            Project(name: "云栖写字楼配电改造", location: "高新区", status: .active, customerName: "云栖物业", customerPhone: "13800000002", startDate: day(-9), expectedEndDate: day(20), managerName: "王工", contractAmount: "86000", paidAmount: "30000", paymentStatus: .partial, materialCost: "28000", laborCost: "19000"),
            Project(name: "锦绣府样板间精装", location: "南城区", status: .paused, customerName: "锦绣置业", customerPhone: "13800000003", startDate: day(-61), expectedEndDate: day(15), managerName: "赵工", contractAmount: "62000", paidAmount: "22000", paymentStatus: .partial, materialCost: "21000", laborCost: "15000"),
            Project(name: "科技园弱电升级", location: "北园区", status: .completed, customerName: "星河科技", customerPhone: "13800000004", startDate: day(-79), expectedEndDate: day(-25), managerName: "陈工", contractAmount: "54000", paidAmount: "54000", paymentStatus: .paid, materialCost: "18000", laborCost: "13000"),
            Project(name: "望江会所灯光翻新", location: "滨江区", status: .settled, customerName: "望江会所", customerPhone: "13800000005", startDate: day(-115), expectedEndDate: day(-74), managerName: "周工", contractAmount: "39000", paidAmount: "39000", paymentStatus: .paid, materialCost: "11000", laborCost: "9000"),
            Project(name: "中央厨房电路维保", location: "经开区", status: .archived, customerName: "鲜味餐饮", customerPhone: "13800000006", startDate: day(-183), expectedEndDate: day(-133), managerName: "孙工", contractAmount: "47000", paidAmount: "47000", paymentStatus: .paid, materialCost: "16000", laborCost: "12000")
        ]
        projects = projectsSeed

        let projectByName = Dictionary(uniqueKeysWithValues: projectsSeed.map { ($0.name, $0.id) })
        func requiredProjectID(_ name: String) -> UUID? {
            guard let projectID = projectByName[name] else {
                StorageIssueLog.record("示例数据项目映射缺失：\(name)，已跳过关联记录", category: .dataStore)
                return nil
            }
            return projectID
        }

        materialItems = [
            MaterialItem(name: "BV 2.5mm² 电线", quantity: "6", unit: "卷", unitPrice: "285", purchaseStatus: .purchased, arrivalDate: day(-8), projectId: projectByName["阳光花园 3# 楼"]),
            MaterialItem(name: "BV 2.5mm² 电线", quantity: "4", unit: "卷", unitPrice: "326", supplier: "供应商A", purchaseStatus: .arrived, arrivalDate: day(-1), projectId: projectByName["阳光花园 3# 楼"]),
            MaterialItem(name: "86 型底盒", quantity: "48", unit: "个", unitPrice: "2.8", purchaseStatus: .arrived, arrivalDate: day(-7), projectId: projectByName["阳光花园 3# 楼"]),
            MaterialItem(name: "LED 平板灯", quantity: "36", unit: "套", unitPrice: "92", specification: "600×600", brand: "欧普", supplier: "供应商D", purchaseStatus: .purchased, arrivalDate: day(1), projectId: projectByName["阳光花园 3# 楼"]),
            MaterialItem(name: "阻燃线管 Φ20", quantity: "260", unit: "米", unitPrice: "1.9", purchaseStatus: .purchased, arrivalDate: day(-9), projectId: projectByName["云栖写字楼配电改造"]),
            MaterialItem(name: "阻燃线管 Φ20", quantity: "180", unit: "米", unitPrice: "2.35", supplier: "供应商B", purchaseStatus: .arrived, arrivalDate: day(-1), projectId: projectByName["云栖写字楼配电改造"]),
            MaterialItem(name: "配电箱 18 回路", quantity: "4", unit: "台", unitPrice: "960", purchaseStatus: .notPurchased, arrivalDate: "", projectId: projectByName["云栖写字楼配电改造"]),
            MaterialItem(name: "镀锌桥架", quantity: "86", unit: "米", unitPrice: "68", specification: "200×100", brand: "本地", supplier: "供应商B", purchaseStatus: .arrived, arrivalDate: day(-5), projectId: projectByName["云栖写字楼配电改造"]),
            MaterialItem(name: "轻钢龙骨", quantity: "120", unit: "根", unitPrice: "24", purchaseStatus: .arrived, arrivalDate: day(-43), projectId: projectByName["锦绣府样板间精装"]),
            MaterialItem(name: "石膏板", quantity: "85", unit: "张", unitPrice: "38", purchaseStatus: .used, arrivalDate: day(-43), projectId: projectByName["锦绣府样板间精装"]),
            MaterialItem(name: "乳胶漆", quantity: "12", unit: "桶", unitPrice: "185", specification: "20kg", brand: "立邦", supplier: "供应商E", purchaseStatus: .notPurchased, arrivalDate: "", projectId: projectByName["锦绣府样板间精装"]),
            MaterialItem(name: "网线 Cat6", quantity: "9", unit: "箱", unitPrice: "430", purchaseStatus: .used, arrivalDate: day(-69), projectId: projectByName["科技园弱电升级"]),
            MaterialItem(name: "监控电源", quantity: "22", unit: "个", unitPrice: "45", purchaseStatus: .used, arrivalDate: day(-70), projectId: projectByName["科技园弱电升级"]),
            MaterialItem(name: "摄像机支架", quantity: "18", unit: "个", unitPrice: "28", specification: "鸭嘴支架", supplier: "供应商F", purchaseStatus: .used, arrivalDate: day(-68), projectId: projectByName["科技园弱电升级"])
        ]

        quoteItems = [
            QuoteItem(name: "室内布线", unitPrice: "46", quantity: "820", unit: "米", notes: "含人工辅材", taxRate: "3", discountRate: "0", versionName: "V2", status: .sent, customerConfirmedDate: day(-6), contractAmount: "37720", projectId: projectByName["阳光花园 3# 楼"]),
            QuoteItem(name: "配电箱安装", unitPrice: "920", quantity: "4", unit: "台", notes: "待客户确认品牌", taxRate: "3", discountRate: "2", versionName: "V1", status: .draft, customerConfirmedDate: "", contractAmount: "3600", projectId: projectByName["云栖写字楼配电改造"]),
            QuoteItem(name: "石膏吊顶", unitPrice: "138", quantity: "210", unit: "㎡", notes: "", taxRate: "0", discountRate: "3", versionName: "V3", status: .confirmed, customerConfirmedDate: day(-59), contractAmount: "28140", projectId: projectByName["锦绣府样板间精装"]),
            QuoteItem(name: "弱电布控", unitPrice: "72", quantity: "380", unit: "点", notes: "", taxRate: "0", discountRate: "0", versionName: "V1", status: .confirmed, customerConfirmedDate: day(-75), contractAmount: "27360", projectId: projectByName["科技园弱电升级"])
        ]

        laborRecords = [
            LaborRecord(date: day(-7), workers: "6", hours: "8", unitRate: "130", workType: "电工", teamName: "A组", note: "三层主线敷设", projectId: projectByName["阳光花园 3# 楼"]),
            LaborRecord(date: day(-6), workers: "4", hours: "9", unitRate: "145", workType: "电工", teamName: "B组", note: "桥架改造", projectId: projectByName["云栖写字楼配电改造"]),
            LaborRecord(date: day(-56), workers: "5", hours: "8", unitRate: "120", workType: "木工", teamName: "精装组", note: "吊顶封板", projectId: projectByName["锦绣府样板间精装"]),
            LaborRecord(date: day(-53), workers: "3", hours: "8", unitRate: "118", workType: "弱电", teamName: "弱电组", note: "调试摄像头", projectId: projectByName["科技园弱电升级"])
        ]

        dailyLogs = [
            DailyLog(date: day(0), weather: "晴", content: "公共区域灯具定位复核，完成样板段试装", workers: "7", photoFileName: nil, safety: "梯具防滑垫检查通过", materials: "LED 平板灯到货待验收", tomorrowPlan: "完成走道灯具安装", qualityIssue: "局部吊顶开孔偏差 8mm", rectification: "明日统一修正开孔", confirmer: "李工", projectId: projectByName["阳光花园 3# 楼"]),
            DailyLog(date: day(-1), weather: "阵雨", content: "配电间新增回路穿线，桥架支架补强", workers: "5", photoFileName: nil, safety: "雨天材料转运防滑提醒", materials: "阻燃线管补货 180 米", tomorrowPlan: "完成端子编号和回路测试", qualityIssue: "", rectification: "", confirmer: "王工", projectId: projectByName["云栖写字楼配电改造"]),
            DailyLog(date: day(-7), weather: "晴", content: "完成 3 层主线敷设与桥架固定", workers: "6", photoFileName: nil, safety: "班前工具绝缘检查通过", materials: "BV线与线管到场", tomorrowPlan: "完成分户箱接线", qualityIssue: "", rectification: "", confirmer: "李工", projectId: projectByName["阳光花园 3# 楼"]),
            DailyLog(date: day(-6), weather: "多云", content: "拆旧桥架并安装新桥架 60 米", workers: "4", photoFileName: nil, safety: "高处作业佩戴安全带", materials: "桥架配件补货", tomorrowPlan: "配电间回路整理", qualityIssue: "旧线标识混乱", rectification: "统一套管标号", confirmer: "王工", projectId: projectByName["云栖写字楼配电改造"]),
            DailyLog(date: day(-56), weather: "阴", content: "样板间吊顶龙骨加固", workers: "5", photoFileName: nil, safety: "脚手架复检", materials: "石膏板 40 张", tomorrowPlan: "批灰找平", qualityIssue: "", rectification: "", confirmer: "赵工", projectId: projectByName["锦绣府样板间精装"])
        ]

        historyRecords = [
            HistoryRecord(tool: "电流计算", input: "12kW / 220V", result: "54.55 A", date: dateTime(-7, 16, 40)),
            HistoryRecord(tool: "照明估算", input: "120㎡ 办公区 / 350lux", result: "24 盏", date: dateTime(-8, 10, 12)),
            HistoryRecord(tool: "线管穿线率", input: "Φ20 管, 3×2.5mm²", result: "44.8%", date: dateTime(-9, 9, 5)),
            HistoryRecord(tool: "桥架填充率", input: "200×100 桥架, 12 回路", result: "58.1%", date: dateTime(-11, 14, 26))
        ]

        progressTasks = [
            requiredProjectID("阳光花园 3# 楼").map { ProgressTask(projectId: $0, title: "三层主线敷设", startDate: day(-9), dueDate: day(-2), completion: 0.72, note: "待穿线复核") },
            requiredProjectID("阳光花园 3# 楼").map { ProgressTask(projectId: $0, title: "分户箱接线", startDate: day(-4), dueDate: day(2), completion: 0.25, note: "") },
            requiredProjectID("云栖写字楼配电改造").map { ProgressTask(projectId: $0, title: "桥架更新", startDate: day(-8), dueDate: day(0), completion: 0.65, note: "") },
            requiredProjectID("云栖写字楼配电改造").map { ProgressTask(projectId: $0, title: "配电间回路整理", startDate: day(-1), dueDate: day(4), completion: 0.15, note: "待停电窗口") },
            requiredProjectID("锦绣府样板间精装").map { ProgressTask(projectId: $0, title: "吊顶封板", startDate: day(-59), dueDate: day(-43), completion: 0.8, note: "暂停，待业主选型") },
            requiredProjectID("科技园弱电升级").map { ProgressTask(projectId: $0, title: "网络调试验收", startDate: day(-30), dueDate: day(-26), completion: 1.0, note: "已完成") }
        ].compactMap { $0 }

        lightingCircuitPlans = [
            LightingCircuitPlan(
                name: "阳光花园公共照明",
                projectId: projectByName["阳光花园 3# 楼"],
                supplyType: .singlePhase,
                voltage: "220",
                powerFactor: "0.90",
                demandFactor: "0.88",
                breakerFactor: "1.25",
                wireFactor: "1.15",
                isCopper: true,
                loads: [
                    LightingCircuitLoad(name: "楼梯间照明", powerKW: "1.4"),
                    LightingCircuitLoad(name: "走道照明", powerKW: "2.1")
                ],
                updatedAt: dateTime(-7, 18, 20)
            ),
            LightingCircuitPlan(
                name: "云栖办公区照明",
                projectId: projectByName["云栖写字楼配电改造"],
                supplyType: .threePhase,
                voltage: "380",
                powerFactor: "0.92",
                demandFactor: "0.85",
                breakerFactor: "1.20",
                wireFactor: "1.10",
                isCopper: true,
                loads: [
                    LightingCircuitLoad(name: "A 区办公", powerKW: "3.2"),
                    LightingCircuitLoad(name: "B 区办公", powerKW: "2.8"),
                    LightingCircuitLoad(name: "会议区", powerKW: "1.6")
                ],
                updatedAt: dateTime(-6, 11, 36)
            )
        ]

        siteTodos = [
            SiteTodo(title: "确认 LED 灯具色温样品", owner: "李工", dueDate: day(0), priority: .high, issueType: .material, isDone: false, note: "3000K/4000K 各留一套给业主确认", projectId: projectByName["阳光花园 3# 楼"]),
            SiteTodo(title: "复核三层配电箱回路编号", owner: "李工", dueDate: day(-4), priority: .high, issueType: .quality, isDone: false, note: "与图纸版本 V2 对齐", projectId: projectByName["阳光花园 3# 楼"]),
            SiteTodo(title: "补齐公共照明报价单价", owner: "材料员", dueDate: day(-9), priority: .medium, issueType: .material, isDone: false, note: "已逾期待处理", projectId: projectByName["阳光花园 3# 楼"]),
            SiteTodo(title: "桥架支架间距复核", owner: "王工", dueDate: day(-3), priority: .high, issueType: .safety, isDone: false, note: "", projectId: projectByName["云栖写字楼配电改造"]),
            SiteTodo(title: "缺票流水补开专票", owner: "财务", dueDate: day(2), priority: .medium, issueType: .general, isDone: false, note: "供应商B 桥架材料款缺票", projectId: projectByName["云栖写字楼配电改造"]),
            SiteTodo(title: "样板间吊顶收口确认", owner: "赵工", dueDate: day(-45), priority: .low, issueType: .general, isDone: true, completedAt: dateTime(-46, 17, 40), note: "", projectId: projectByName["锦绣府样板间精装"])
        ]

        projectDrawings = []
        projectDocuments = []

        projectContacts = [
            requiredProjectID("阳光花园 3# 楼").map { ProjectContact(projectId: $0, relatedProjectIds: [projectByName["望江会所灯光翻新"]].compactMap { $0 }, name: "刘总", role: .owner, company: "宏远地产", phone: "13900010001", note: "业主代表，历史合作客户") },
            requiredProjectID("阳光花园 3# 楼").map { ProjectContact(projectId: $0, name: "马工", role: .supervisor, company: "监理单位", phone: "13900010002", note: "") },
            requiredProjectID("云栖写字楼配电改造").map { ProjectContact(projectId: $0, name: "黄经理", role: .owner, company: "云栖物业", phone: "13900010003", note: "") },
            requiredProjectID("云栖写字楼配电改造").map { ProjectContact(projectId: $0, relatedProjectIds: [projectByName["中央厨房电路维保"]].compactMap { $0 }, name: "陈经理", role: .supplier, company: "供应商B", phone: "13700020002", note: "桥架、线管常用供应商") },
            requiredProjectID("锦绣府样板间精装").map { ProjectContact(projectId: $0, name: "吴工", role: .team, company: "精装班组", phone: "13900010004", note: "暂停中") },
            requiredProjectID("阳光花园 3# 楼").map { ProjectContact(projectId: $0, relatedProjectIds: [projectByName["云栖写字楼配电改造"]].compactMap { $0 }, name: "张班组", role: .team, company: "电气施工A组", phone: "13900010005", note: "可跨项目调配") }
        ].compactMap { $0 }

        projectFinancialRecords = [
            requiredProjectID("阳光花园 3# 楼").map { ProjectFinancialRecord(projectId: $0, date: day(-5), direction: .income, category: .collection, amount: "18000", counterparty: "宏远地产", invoiceNumber: "SK-20260505-01", status: .active, dueDate: day(0), reminderStatus: .pending, note: "二期收款") },
            requiredProjectID("阳光花园 3# 楼").map { ProjectFinancialRecord(projectId: $0, date: day(-6), direction: .expense, category: .material, amount: "8600", counterparty: "材料供应商A", invoiceNumber: "FP-20260504-09", status: .active, note: "线管与底盒") },
            requiredProjectID("阳光花园 3# 楼").map { ProjectFinancialRecord(projectId: $0, date: day(-1), direction: .expense, category: .material, amount: "3312", counterparty: "供应商D", invoiceNumber: "", status: .active, dueDate: day(3), reminderStatus: .pending, note: "LED 平板灯首批，待补发票") },
            requiredProjectID("阳光花园 3# 楼").map { ProjectFinancialRecord(projectId: $0, date: day(-2), direction: .income, category: .paymentRequest, amount: "26000", counterparty: "宏远地产", invoiceNumber: "", status: .draft, dueDate: day(5), reminderStatus: .none, note: "公共区域变更请款草稿") },
            requiredProjectID("云栖写字楼配电改造").map { ProjectFinancialRecord(projectId: $0, date: day(-6), direction: .expense, category: .labor, amount: "5200", counterparty: "施工班组B", invoiceNumber: "", status: .active, note: "桥架施工人工") },
            requiredProjectID("云栖写字楼配电改造").map { ProjectFinancialRecord(projectId: $0, date: day(-1), direction: .expense, category: .material, amount: "4230", counterparty: "供应商B", invoiceNumber: "", status: .active, dueDate: day(1), reminderStatus: .pending, note: "线管补货，缺票匹配测试") },
            requiredProjectID("锦绣府样板间精装").map { ProjectFinancialRecord(projectId: $0, date: day(-44), direction: .expense, category: .labor, amount: "4800", counterparty: "精装班组", invoiceNumber: "", status: .active, dueDate: day(-30), reminderStatus: .reminded, note: "暂停前人工尾款未结") },
            requiredProjectID("科技园弱电升级").map { ProjectFinancialRecord(projectId: $0, date: day(-25), direction: .income, category: .collection, amount: "24000", counterparty: "星河科技", invoiceNumber: "SK-20260415-02", status: .active, reminderStatus: .done, note: "项目结算收款") }
        ].compactMap { $0 }

        quickNotes = [
            QuickNote(title: "阳光花园交底纪要", content: "客户要求公共区域照明增加双控。", projectId: projectByName["阳光花园 3# 楼"], createdAt: dateTime(-7, 20, 10), updatedAt: dateTime(-7, 20, 10)),
            QuickNote(title: "云栖配电间照片已确认", content: "旧线清理完毕，明天开始回路重排。", projectId: projectByName["云栖写字楼配电改造"], createdAt: dateTime(-6, 18, 6), updatedAt: dateTime(-6, 18, 6)),
            QuickNote(title: "样板间暂停事项", content: "等待业主确认灯具色温。", projectId: projectByName["锦绣府样板间精装"], createdAt: dateTime(-45, 9, 22), updatedAt: dateTime(-45, 9, 22))
        ]

        projectWarehouseMovements = [
            requiredProjectID("阳光花园 3# 楼").map { ProjectWarehouseMovement(projectId: $0, date: day(-8), movementType: .inbound, materialName: "BV 2.5mm² 电线", specification: "100m/卷", unit: "卷", quantity: "6", counterparty: "供应商A", handler: "材料员", note: "首批进场") },
            requiredProjectID("阳光花园 3# 楼").map { ProjectWarehouseMovement(projectId: $0, date: day(-1), movementType: .inbound, materialName: "LED 平板灯", specification: "600×600", unit: "套", quantity: "36", counterparty: "供应商D", handler: "材料员", note: "待业主确认色温") },
            requiredProjectID("阳光花园 3# 楼").map { ProjectWarehouseMovement(projectId: $0, date: day(-6), movementType: .outbound, materialName: "86 型底盒", specification: "阻燃", unit: "个", quantity: "20", counterparty: "施工A组", handler: "库管", note: "三层施工领用") },
            requiredProjectID("云栖写字楼配电改造").map { ProjectWarehouseMovement(projectId: $0, date: day(-7), movementType: .inbound, materialName: "阻燃线管 Φ20", specification: "国标", unit: "米", quantity: "260", counterparty: "供应商B", handler: "库管", note: "") },
            requiredProjectID("云栖写字楼配电改造").map { ProjectWarehouseMovement(projectId: $0, date: day(-5), movementType: .inbound, materialName: "镀锌桥架", specification: "200×100", unit: "米", quantity: "86", counterparty: "供应商B", handler: "库管", note: "按一层配电间先到") },
            requiredProjectID("云栖写字楼配电改造").map { ProjectWarehouseMovement(projectId: $0, date: day(-1), movementType: .outbound, materialName: "配电箱 18 回路", specification: "18回路", unit: "台", quantity: "5", counterparty: "施工B组", handler: "库管", note: "故意制造负库存，用于风险测试") }
        ].compactMap { $0 }

        templates = [
            ProjectTemplate(name: "住宅电气改造", category: .quotation, content: "布线 ¥45/m\n插座安装 ¥25/个\n配电箱 ¥800/台"),
            ProjectTemplate(name: "办公楼配电改造", category: .quotation, content: "桥架安装 ¥65/m\n回路整理 ¥280/回路\n配电箱调试 ¥1200/台"),
            ProjectTemplate(name: "标准施工日志", category: .dailyLog, content: "日期:\n天气:\n出勤人数:\n施工内容:\n安全问题:\n材料进场:\n质量问题:\n明日计划:"),
            ProjectTemplate(name: "住宅布线材料", category: .material, content: "BV 2.5mm² 电线 × 3卷\nBV 4mm² 电线 × 2卷\n线管 Φ20 × 50m\n86盒 × 20个")
        ]

        materialPriceEntries = [
            MaterialPriceEntry(name: "BV 铜芯线", specification: "2.5mm²", brand: "常用", unit: "卷(100m)", referencePrice: "285", supplier: "供应商A", category: "电线", updatedAt: dateTime(-8, 9, 20)),
            MaterialPriceEntry(name: "BV 铜芯线", specification: "2.5mm²", brand: "常用", unit: "卷(100m)", referencePrice: "326", supplier: "供应商A", category: "电线", note: "近期铜价上涨", updatedAt: dateTime(-1, 9, 10)),
            MaterialPriceEntry(name: "BV 铜芯线", specification: "4mm²", brand: "常用", unit: "卷(100m)", referencePrice: "395", supplier: "供应商A", category: "电线", updatedAt: dateTime(-5, 11, 0)),
            MaterialPriceEntry(name: "阻燃线管", specification: "Φ20", brand: "常用", unit: "米", referencePrice: "1.9", supplier: "供应商B", category: "线管", updatedAt: dateTime(-9, 10, 15)),
            MaterialPriceEntry(name: "阻燃线管", specification: "Φ20", brand: "常用", unit: "米", referencePrice: "2.35", supplier: "供应商B", category: "线管", note: "补货价上涨", updatedAt: dateTime(-1, 15, 45)),
            MaterialPriceEntry(name: "配电箱", specification: "18回路", brand: "常用", unit: "台", referencePrice: "960", supplier: "供应商C", category: "配电设备"),
            MaterialPriceEntry(name: "LED 平板灯", specification: "600×600", brand: "欧普", unit: "套", referencePrice: "92", supplier: "供应商D", category: "灯具"),
            MaterialPriceEntry(name: "镀锌桥架", specification: "200×100", brand: "本地", unit: "米", referencePrice: "68", supplier: "供应商B", category: "桥架")
        ]

        materialSheetDrafts = [
            MaterialSheetDraft(
                title: "阳光花园公共照明补料单",
                projectId: projectByName["阳光花园 3# 楼"],
                exportProjectName: "阳光花园 3# 楼",
                exportPreparer: "李工",
                exportDate: day(0),
                items: [
                    MaterialSheetDraftItem(name: "LED 平板灯", specification: "600×600 / 4000K", unit: "套", quantity: "36", unitPrice: "92", laborCost: "18", supplier: "供应商D", usageLocation: "公共走道", note: "业主确认色温后下单"),
                    MaterialSheetDraftItem(name: "BV 2.5mm² 电线", specification: "100m/卷", unit: "卷", quantity: "4", unitPrice: "326", laborCost: "0", supplier: "供应商A", usageLocation: "走道照明", note: "价格异动测试"),
                    MaterialSheetDraftItem(name: "86 型底盒", specification: "阻燃", unit: "个", quantity: "30", unitPrice: "2.8", laborCost: "1.2", supplier: "供应商A", usageLocation: "公共区域", note: "")
                ],
                createdAt: dateTime(-1, 18, 0),
                updatedAt: dateTime(0, 9, 20)
            ),
            MaterialSheetDraft(
                title: "云栖配电间桥架补料单",
                projectId: projectByName["云栖写字楼配电改造"],
                exportProjectName: "云栖写字楼配电改造",
                exportPreparer: "王工",
                exportDate: day(-1),
                items: [
                    MaterialSheetDraftItem(name: "镀锌桥架", specification: "200×100", unit: "米", quantity: "54", unitPrice: "68", laborCost: "22", supplier: "供应商B", usageLocation: "配电间", note: "需现场复尺"),
                    MaterialSheetDraftItem(name: "阻燃线管 Φ20", specification: "国标", unit: "米", quantity: "180", unitPrice: "2.35", laborCost: "1.5", supplier: "供应商B", usageLocation: "办公区回路", note: "补货价上涨")
                ],
                createdAt: dateTime(-2, 10, 30),
                updatedAt: dateTime(-1, 17, 15)
            )
        ]
        supplierProfiles = [
            SupplierProfile(name: "供应商A", category: "电气主材", contact: "陈经理", phone: "13700020001", address: "城东仓", note: ""),
            SupplierProfile(name: "供应商B", category: "线管桥架", contact: "刘经理", phone: "13700020002", address: "高新区仓", note: ""),
            SupplierProfile(name: "供应商C", category: "配电设备", contact: "王经理", phone: "13700020003", address: "北园仓", note: ""),
            SupplierProfile(name: "供应商D", category: "灯具", contact: "周经理", phone: "13700020004", address: "灯具市场 3 区", note: "支持当天补货"),
            SupplierProfile(name: "供应商E", category: "精装辅材", contact: "吴经理", phone: "13700020005", address: "南城仓", note: "油漆、腻子常用")
        ]

        constructionMethods = [
            ConstructionMethod(title: "电线穿管施工", trade: "电气", versionName: "V2", publishStatus: .published, steps: "1. 清理管路\n2. 穿引线\n3. 分色穿线\n4. 绝缘测试", qualityStandard: "线色正确，管内无接头，绝缘测试合格", safetyNotes: "断电作业，穿线时防止划伤绝缘层", updatedAt: dateTime(-7, 8, 50)),
            ConstructionMethod(title: "桥架安装与接地", trade: "电气", versionName: "V1", publishStatus: .draft, steps: "1. 放线定位\n2. 固定支架\n3. 拼装桥架\n4. 接地跨接", qualityStandard: "水平垂直偏差符合规范，跨接连续可靠", safetyNotes: "高处作业佩戴安全带，切割防护到位", updatedAt: dateTime(-8, 16, 10)),
            ConstructionMethod(title: "灯具安装与通电测试", trade: "电气", versionName: "V1", publishStatus: .published, steps: "1. 核对灯具型号\n2. 检查吊顶开孔\n3. 接线固定\n4. 分区通电测试", qualityStandard: "灯具排列顺直，色温一致，无闪烁", safetyNotes: "通电前复核绝缘，登高使用合格梯具", updatedAt: dateTime(-1, 12, 0))
        ]

        userMaterials = [
            UserMaterial(name: "抗震支架", specification: "DN100", unit: "套", category: "安装辅材"),
            UserMaterial(name: "防火泥", specification: "2kg/包", unit: "包", category: "防火封堵"),
            UserMaterial(name: "桥架跨接线", specification: "4mm²", unit: "根", category: "接地材料")
        ]
        deletedUserMaterials = []
        favoriteMaterialKeys = [
            MaterialIdentity.key(name: "BV 铜芯线", specification: "2.5mm²", unit: "卷(100m)"),
            MaterialIdentity.key(name: "阻燃线管", specification: "Φ20", unit: "米"),
            MaterialIdentity.key(name: "LED 平板灯", specification: "600×600", unit: "套")
        ]
        recentMaterialKeys = [
            MaterialIdentity.key(name: "LED 平板灯", specification: "600×600", unit: "套"),
            MaterialIdentity.key(name: "镀锌桥架", specification: "200×100", unit: "米"),
            MaterialIdentity.key(name: "抗震支架", specification: "DN100", unit: "套")
        ]
    }
}
#endif
