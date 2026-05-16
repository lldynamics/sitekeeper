import Foundation

enum CADDrawingTextEncoding: String, CaseIterable, Codable {
    case auto
    case gbk936
    case gb18030
    case big5950

    var displayName: String {
        switch self {
        case .auto:
            return "自动（推荐）"
        case .gbk936:
            return "简中 GBK（CP936）"
        case .gb18030:
            return "简中 GB18030（54936）"
        case .big5950:
            return "繁中 Big5（CP950）"
        }
    }

    var codePageOverride: Int32? {
        switch self {
        case .auto:
            return nil
        case .gbk936:
            return 936
        case .gb18030:
            return 54936
        case .big5950:
            return 950
        }
    }
}

enum CADDrawingTextBigFont: String, CaseIterable, Codable, Sendable {
    case auto
    case gbcbig
    case hztxt
    case hzfs
    case big5

    var displayName: String {
        switch self {
        case .auto:
            return "自动 SHX/大字体"
        case .gbcbig:
            return "简中 GBCBIG（含 tssdeng/tssdchn）"
        case .hztxt:
            return "简中 HZTXT（含 simplex/txt）"
        case .hzfs:
            return "仿宋 HZFS（含 simfang）"
        case .big5:
            return "繁中 Big5"
        }
    }

    var bridgeCode: Int32? {
        switch self {
        case .auto:
            return 0
        case .gbcbig:
            return 1
        case .hztxt:
            return 2
        case .hzfs:
            return 3
        case .big5:
            return 4
        }
    }
}

extension CADDrawingTextBigFont {
    static func inferredFromFontName(_ rawName: String) -> CADDrawingTextBigFont {
        let normalized = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "\\.(shx|shp|fon)$", with: "", options: .regularExpression)

        let tokens = Set(
            [normalized] +
            normalized.components(separatedBy: CharacterSet(charactersIn: "/\\._- ()[]{}<>+"))
                .filter { !$0.isEmpty }
        )

        let big5Aliases: Set<String> = ["big5", "chineset", "chinese_t", "cht", "mingliu", "pmingliu", "kaiu", "msung", "bkai"]
        let hzfsAliases: Set<String> = ["hzfs", "hzfs1", "hzfs2", "hzfangsong", "fs", "fs1", "fs2"]
        let hztxtAliases: Set<String> = ["hztxt", "hztxt1", "hztxt2", "hztext", "txt", "simplex", "romans", "romanc", "romand", "isocp"]
        let gbcbigAliases: Set<String> = ["gbcbig", "gbcbiggb", "gbtxt", "gbenor", "gbeitc", "gbhz", "gbfs", "tssdeng", "tssdchn", "tssd", "chinesegb"]

        if !tokens.isDisjoint(with: big5Aliases) { return .big5 }
        if !tokens.isDisjoint(with: hzfsAliases) { return .hzfs }
        if !tokens.isDisjoint(with: hztxtAliases) { return .hztxt }
        if !tokens.isDisjoint(with: gbcbigAliases) { return .gbcbig }
        return .auto
    }
}

enum CADProjectFontMappingSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case bigFontFile = "bigfont"
    case fontFile = "font"
    case styleName = "style"
    case any = "any"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bigFontFile:
            return "大字体文件"
        case .fontFile:
            return "字体文件"
        case .styleName:
            return "文字样式"
        case .any:
            return "任意匹配"
        }
    }
}

struct CADProjectFontMapping: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var source: CADProjectFontMappingSource
    var pattern: String
    var bigFont: CADDrawingTextBigFont

    init(
        id: UUID = UUID(),
        source: CADProjectFontMappingSource = .bigFontFile,
        pattern: String,
        bigFont: CADDrawingTextBigFont = .gbcbig
    ) {
        self.id = id
        self.source = source
        self.pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bigFont = bigFont
    }

    enum CodingKeys: String, CodingKey {
        case id, source, pattern, bigFont
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try container.decodeStringEnum(
            CADProjectFontMappingSource.self,
            forKey: .source,
            default: .bigFontFile
        )
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        bigFont = try container.decodeStringEnum(
            CADDrawingTextBigFont.self,
            forKey: .bigFont,
            default: .gbcbig
        )
    }

    var normalizedPattern: String {
        pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isUsable: Bool {
        !normalizedPattern.isEmpty && bigFont.bridgeCode != nil && bigFont != .auto
    }

    var deduplicationKey: String {
        let folded = normalizedPattern
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return "\(source.rawValue)|\(folded)"
    }
}

struct CADDrawingTextSchemeSnapshot: Codable, Equatable {
    var codePage: Int32?
    var bigFont: Int32?
    var styleName: String?
    var fontFile: String?
    var bigFontFile: String?
    var autoDetectScore: Int?
    var styleSummary: String?
    var matchedFontSummary: String?
    var unresolvedFontSummary: String?
    var fontResolutionSummary: String?
    var rawTextBytesHexSample: String?
    var detectionSummary: String?

    init(
        codePage: Int32? = nil,
        bigFont: Int32? = nil,
        styleName: String? = nil,
        fontFile: String? = nil,
        bigFontFile: String? = nil,
        autoDetectScore: Int? = nil,
        styleSummary: String? = nil,
        matchedFontSummary: String? = nil,
        unresolvedFontSummary: String? = nil,
        fontResolutionSummary: String? = nil,
        rawTextBytesHexSample: String? = nil,
        detectionSummary: String? = nil
    ) {
        self.codePage = codePage
        self.bigFont = bigFont
        self.styleName = styleName
        self.fontFile = fontFile
        self.bigFontFile = bigFontFile
        self.autoDetectScore = autoDetectScore
        self.styleSummary = styleSummary
        self.matchedFontSummary = matchedFontSummary
        self.unresolvedFontSummary = unresolvedFontSummary
        self.fontResolutionSummary = fontResolutionSummary
        self.rawTextBytesHexSample = rawTextBytesHexSample
        self.detectionSummary = detectionSummary
    }
}

struct CADDrawingViewState: Codable, Equatable {
    var zoomScale: Double
    var panOffsetX: Double
    var panOffsetY: Double
    var viewportCenterX: Double?
    var viewportCenterY: Double?
    var usesSavedVisibleLayers: Bool
    var visibleLayerNames: [String]

    enum CodingKeys: String, CodingKey {
        case zoomScale
        case panOffsetX
        case panOffsetY
        case viewportCenterX
        case viewportCenterY
        case usesSavedVisibleLayers
        case visibleLayerNames
    }

    init(
        zoomScale: Double = 1,
        panOffsetX: Double = 0,
        panOffsetY: Double = 0,
        viewportCenterX: Double? = nil,
        viewportCenterY: Double? = nil,
        usesSavedVisibleLayers: Bool = false,
        visibleLayerNames: [String] = []
    ) {
        self.zoomScale = zoomScale
        self.panOffsetX = panOffsetX
        self.panOffsetY = panOffsetY
        self.viewportCenterX = viewportCenterX
        self.viewportCenterY = viewportCenterY
        self.usesSavedVisibleLayers = usesSavedVisibleLayers
        self.visibleLayerNames = visibleLayerNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoomScale = try container.decodeIfPresent(Double.self, forKey: .zoomScale) ?? 1
        panOffsetX = try container.decodeIfPresent(Double.self, forKey: .panOffsetX) ?? 0
        panOffsetY = try container.decodeIfPresent(Double.self, forKey: .panOffsetY) ?? 0
        viewportCenterX = try container.decodeIfPresent(Double.self, forKey: .viewportCenterX)
        viewportCenterY = try container.decodeIfPresent(Double.self, forKey: .viewportCenterY)
        visibleLayerNames = try container.decodeIfPresent([String].self, forKey: .visibleLayerNames) ?? []
        usesSavedVisibleLayers = try container.decodeIfPresent(Bool.self, forKey: .usesSavedVisibleLayers) ?? !visibleLayerNames.isEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(zoomScale, forKey: .zoomScale)
        try container.encode(panOffsetX, forKey: .panOffsetX)
        try container.encode(panOffsetY, forKey: .panOffsetY)
        try container.encodeIfPresent(viewportCenterX, forKey: .viewportCenterX)
        try container.encodeIfPresent(viewportCenterY, forKey: .viewportCenterY)
        try container.encode(usesSavedVisibleLayers, forKey: .usesSavedVisibleLayers)
        try container.encode(visibleLayerNames, forKey: .visibleLayerNames)
    }

    var hasSavedViewport: Bool {
        zoomScale > 1.0001 ||
        abs(panOffsetX) > 0.5 ||
        abs(panOffsetY) > 0.5 ||
        (viewportCenterX != nil && viewportCenterY != nil) ||
        usesSavedVisibleLayers
    }
}

struct ProjectDrawing: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var name: String
    var fileName: String
    var fileType: String
    var version: String
    var isCurrentVersion: Bool
    var relatedLogDate: String
    var issueStatus: DrawingIssueStatus
    var issueNote: String
    var textEncoding: CADDrawingTextEncoding
    var textBigFont: CADDrawingTextBigFont
    var textSchemeSnapshot: CADDrawingTextSchemeSnapshot
    var cadViewState: CADDrawingViewState
    var importedAt: String
    var note: String
    var cadOverlaySnapshotData: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        fileName: String,
        fileType: String,
        version: String = "V1",
        isCurrentVersion: Bool = true,
        relatedLogDate: String = "",
        issueStatus: DrawingIssueStatus = .none,
        issueNote: String = "",
        textEncoding: CADDrawingTextEncoding = .auto,
        textBigFont: CADDrawingTextBigFont = .auto,
        textSchemeSnapshot: CADDrawingTextSchemeSnapshot = .init(),
        cadViewState: CADDrawingViewState = .init(),
        importedAt: String = Formatters.now(),
        note: String = "",
        cadOverlaySnapshotData: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.fileName = fileName
        self.fileType = fileType
        self.version = version
        self.isCurrentVersion = isCurrentVersion
        self.relatedLogDate = relatedLogDate
        self.issueStatus = issueStatus
        self.issueNote = issueNote
        self.textEncoding = textEncoding
        self.textBigFont = textBigFont
        self.textSchemeSnapshot = textSchemeSnapshot
        self.cadViewState = cadViewState
        self.importedAt = importedAt
        self.note = note
        self.cadOverlaySnapshotData = cadOverlaySnapshotData
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, name, fileName, fileType, version, isCurrentVersion, relatedLogDate, issueStatus, issueNote, textEncoding, textBigFont, textSchemeSnapshot, cadViewState, importedAt, note, cadOverlaySnapshotData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "V1"
        isCurrentVersion = try container.decodeIfPresent(Bool.self, forKey: .isCurrentVersion) ?? true
        relatedLogDate = try container.decodeIfPresent(String.self, forKey: .relatedLogDate) ?? ""
        issueStatus = try container.decodeStringEnum(
            DrawingIssueStatus.self,
            forKey: .issueStatus,
            default: .none
        )
        issueNote = try container.decodeIfPresent(String.self, forKey: .issueNote) ?? ""
        textEncoding = try container.decodeStringEnum(
            CADDrawingTextEncoding.self,
            forKey: .textEncoding,
            default: .auto
        )
        textBigFont = try container.decodeStringEnum(
            CADDrawingTextBigFont.self,
            forKey: .textBigFont,
            default: .auto
        )
        textSchemeSnapshot = try container.decodeIfPresent(CADDrawingTextSchemeSnapshot.self, forKey: .textSchemeSnapshot) ?? .init()
        cadViewState = try container.decodeIfPresent(CADDrawingViewState.self, forKey: .cadViewState) ?? .init()
        importedAt = try container.decodeIfPresent(String.self, forKey: .importedAt) ?? Formatters.now()
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        cadOverlaySnapshotData = try container.decodeIfPresent(String.self, forKey: .cadOverlaySnapshotData) ?? ""
    }

    static let allowedFileExtensions: Set<String> = ["pdf", "dwg", "dxf"]
}

struct ProjectContact: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var relatedProjectIds: [UUID]
    var name: String
    var role: ProjectContactRole
    var company: String
    var phone: String
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        relatedProjectIds: [UUID] = [],
        name: String,
        role: ProjectContactRole = .owner,
        company: String = "",
        phone: String = "",
        note: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.relatedProjectIds = Self.normalizedRelatedProjectIDs(relatedProjectIds, excluding: projectId)
        self.name = name
        self.role = role
        self.company = company
        self.phone = phone
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, relatedProjectIds, name, role, company, phone, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        relatedProjectIds = try container.decodeIfPresent([UUID].self, forKey: .relatedProjectIds) ?? []
        relatedProjectIds = Self.normalizedRelatedProjectIDs(relatedProjectIds, excluding: projectId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try container.decodeStringEnum(
            ProjectContactRole.self,
            forKey: .role,
            default: .owner
        )
        company = try container.decodeIfPresent(String.self, forKey: .company) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    var normalizedRole: ProjectContactRole {
        role
    }

    var roleDisplayName: String {
        normalizedRole.displayName
    }

    var allProjectIDs: [UUID] {
        [projectId] + relatedProjectIds.filter { $0 != projectId }
    }

    func isLinked(to projectID: UUID) -> Bool {
        projectId == projectID || relatedProjectIds.contains(projectID)
    }

    private static func normalizedRelatedProjectIDs(_ projectIDs: [UUID], excluding primaryProjectID: UUID) -> [UUID] {
        var seen = Set<UUID>()
        var results: [UUID] = []
        for id in projectIDs where id != primaryProjectID {
            if seen.insert(id).inserted {
                results.append(id)
            }
        }
        return results
    }
}

struct ProjectDocument: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var title: String
    var category: ProjectDocumentCategory
    var fileName: String
    var fileType: String
    var pageCount: Int
    @NonNegativeNumberText var amount: String
    var linkedFinancialRecordId: UUID?
    var linkedConstructionMethodIDs: [UUID]
    var createdAt: String
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        title: String,
        category: ProjectDocumentCategory = .construction,
        fileName: String,
        fileType: String = "pdf",
        pageCount: Int = 1,
        amount: String = "",
        linkedFinancialRecordId: UUID? = nil,
        linkedConstructionMethodIDs: [UUID] = [],
        createdAt: String = Formatters.now(),
        note: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.category = category
        self.fileName = fileName
        self.fileType = fileType
        self.pageCount = pageCount
        self.amount = amount
        self.linkedFinancialRecordId = linkedFinancialRecordId
        self.linkedConstructionMethodIDs = linkedConstructionMethodIDs
        self.createdAt = createdAt
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, title, category, fileName, fileType, pageCount, amount, linkedFinancialRecordId, linkedConstructionMethodIDs, createdAt, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        category = try container.decodeStringEnum(
            ProjectDocumentCategory.self,
            forKey: .category,
            default: .construction
        )
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType) ?? "pdf"
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 1
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        linkedFinancialRecordId = try container.decodeIfPresent(UUID.self, forKey: .linkedFinancialRecordId)
        linkedConstructionMethodIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedConstructionMethodIDs) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? Formatters.now()
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

enum WarehouseMovementType: String, CaseIterable, Codable {
    case inbound = "入库"
    case outbound = "出库"

    var displayName: String {
        switch self {
        case .inbound:
            return String(localized: "warehouse_movement_type_inbound")
        case .outbound:
            return String(localized: "warehouse_movement_type_outbound")
        }
    }

    var sign: Double {
        switch self {
        case .inbound: return 1
        case .outbound: return -1
        }
    }

    var systemImage: String {
        switch self {
        case .inbound: return "tray.and.arrow.down.fill"
        case .outbound: return "tray.and.arrow.up.fill"
        }
    }
}

struct ProjectWarehouseMovement: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var date: String
    var movementType: WarehouseMovementType
    var materialName: String
    var specification: String
    var unit: String
    @NonNegativeNumberText var quantity: String
    var counterparty: String
    var handler: String
    var note: String
    var linkedDocumentIds: [UUID]
    var createdAt: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        date: String = Formatters.date.string(from: Date()),
        movementType: WarehouseMovementType = .inbound,
        materialName: String = "",
        specification: String = "",
        unit: String = "",
        quantity: String = "",
        counterparty: String = "",
        handler: String = "",
        note: String = "",
        linkedDocumentIds: [UUID] = [],
        createdAt: String = Formatters.now()
    ) {
        self.id = id
        self.projectId = projectId
        self.date = date
        self.movementType = movementType
        self.materialName = materialName
        self.specification = specification
        self.unit = unit
        self.quantity = quantity
        self.counterparty = counterparty
        self.handler = handler
        self.note = note
        self.linkedDocumentIds = linkedDocumentIds
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, date, movementType, materialName, specification, unit, quantity, counterparty, handler, note, linkedDocumentIds, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? Formatters.date.string(from: Date())
        movementType = try container.decodeStringEnum(
            WarehouseMovementType.self,
            forKey: .movementType,
            default: .inbound
        )
        materialName = try container.decodeIfPresent(String.self, forKey: .materialName) ?? ""
        specification = try container.decodeIfPresent(String.self, forKey: .specification) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity) ?? ""
        counterparty = try container.decodeIfPresent(String.self, forKey: .counterparty) ?? ""
        handler = try container.decodeIfPresent(String.self, forKey: .handler) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        linkedDocumentIds = try container.decodeIfPresent([UUID].self, forKey: .linkedDocumentIds) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? Formatters.now()
    }

    var normalizedMovementType: WarehouseMovementType {
        movementType
    }
}

struct ProgressTask: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var title: String
    var startDate: String
    var dueDate: String
    var completion: Double
    var note: String

    var clampedCompletion: Double {
        min(max(completion, 0), 1)
    }
}

enum CircuitSupplyType: String, CaseIterable, Codable {
    case singlePhase = "单相回路"
    case threePhase = "三相回路"

    var displayName: String { rawValue }

    var defaultVoltage: String {
        switch self {
        case .singlePhase: return "220"
        case .threePhase: return "380"
        }
    }
}

struct LightingCircuitLoad: Identifiable, Codable {
    var id = UUID()
    var name: String
    var powerKW: String
}

struct LightingCircuitPlan: Identifiable, Codable {
    var id = UUID()
    var name: String
    var projectId: UUID?
    var supplyType: CircuitSupplyType
    var voltage: String
    var powerFactor: String
    var demandFactor: String
    var breakerFactor: String
    var wireFactor: String
    var isCopper: Bool
    var loads: [LightingCircuitLoad]
    var updatedAt: String
}

enum TemplateCategory: String, CaseIterable, Codable {
    case quotation = "报价模板"
    case dailyLog = "日志模板"
    case material = "材料模板"

    var displayName: String {
        switch self {
        case .quotation:
            return String(localized: "报价模板")
        case .dailyLog:
            return String(localized: "日志模板")
        case .material:
            return String(localized: "材料模板")
        }
    }
}

enum DrawingIssueStatus: String, CaseIterable, Codable {
    case none = "无问题"
    case open = "待整改"
    case inProgress = "整改中"
    case closed = "已关闭"

    var displayName: String { rawValue }
}

enum TodoPriority: String, CaseIterable, Codable {
    case high = "高"
    case medium = "中"
    case low = "低"

    var displayName: String { rawValue }
}

enum TodoIssueType: String, CaseIterable, Codable {
    case safety = "安全"
    case quality = "质量"
    case material = "材料"
    case schedule = "进度"
    case general = "其他"

    var displayName: String { rawValue }
}

enum ProjectContactRole: String, CaseIterable, Codable {
    case owner = "业主"
    case customer = "客户"
    case supervisor = "监理"
    case supplier = "供应商"
    case team = "班组"
    case other = "其他"

    var displayName: String { rawValue }
}

enum ProjectDocumentCategory: String, CaseIterable, Codable {
    case paymentRequest = "请款资料"
    case construction = "施工资料"
    case invoice = "发票"
    case receipt = "收据"
    case contract = "合同"
    case acceptance = "验收资料"
    case other = "其他资料"

    var displayName: String { rawValue }
}

enum PhotoTag: String, CaseIterable, Codable {
    case general = "现场"
    case rectificationBefore = "整改前"
    case rectificationAfter = "整改后"
    case hiddenWork = "隐蔽工程"
    case materialArrival = "材料进场"
    case completionAcceptance = "完工验收"

    var displayName: String { rawValue }
}
