import SwiftUI

enum ProjectCreateNumericField: Hashable {
    case contractAmount
    case paidAmount
    case materialCost
    case laborCost
}

struct ProjectCreateSheet: View {
    @Environment(DataStore.self) private var store
    @Binding var name: String
    @Binding var location: String
    @Binding var customerName: String
    @Binding var customerPhone: String
    @Binding var managerName: String
    @Binding var startDate: Date
    @Binding var expectedEndDate: Date
    @Binding var contractAmount: String
    @Binding var paidAmount: String
    @Binding var materialCost: String
    @Binding var laborCost: String
    @Binding var paymentStatus: PaymentStatus
    @Binding var requiredDocumentCategories: Set<ProjectDocumentCategory>
    let focusedField: FocusState<ProjectCreateNumericField?>.Binding
    let canCreate: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void
    @State private var recommendationStage: ProjectDocumentRecommendationStage = .preConstruction

    private var savedDocumentChecklistTemplates: [ProjectDocumentChecklistTemplate] {
        ProjectDocumentChecklistTemplate.customTemplates(from: store.templates)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "工程信息")) {
                    TextField(String(localized: "工程名称"), text: $name)
                        .accessibilityIdentifier("project-create-name")
                    TextField(String(localized: "项目地址"), text: $location, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "负责人"), text: $managerName)
                }
                ProjectDocumentChecklistTemplateSection(
                    selectedCategories: $requiredDocumentCategories,
                    recommendationStage: $recommendationStage,
                    customTemplates: savedDocumentChecklistTemplates
                )
                Section(String(localized: "客户")) {
                    TextField(String(localized: "客户姓名/单位"), text: $customerName)
                    TextField(String(localized: "客户电话"), text: $customerPhone)
                        .keyboardType(.phonePad)
                }
                Section(String(localized: "工期")) {
                    DatePicker(String(localized: "开工日期"), selection: $startDate, displayedComponents: .date)
                    DatePicker(String(localized: "预计完工"), selection: $expectedEndDate, displayedComponents: .date)
                }
                Section(String(localized: "合同与收款")) {
                    LabeledContent(String(localized: "合同金额")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("0", text: $contractAmount.numericInput(.amount))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused(focusedField, equals: .contractAmount)
                            NumericInputValidationHint(
                                validation: InputValidator.validate(
                                    contractAmount,
                                    kind: .amount,
                                    requirement: .optionalNonNegative
                                )
                            )
                        }
                    }
                    LabeledContent(String(localized: "已收款")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("0", text: $paidAmount.numericInput(.amount))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused(focusedField, equals: .paidAmount)
                            NumericInputValidationHint(
                                validation: InputValidator.validate(
                                    paidAmount,
                                    kind: .amount,
                                    requirement: .optionalNonNegative
                                )
                            )
                        }
                    }
                    LabeledContent(String(localized: "材料成本")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("0", text: $materialCost.numericInput(.amount))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused(focusedField, equals: .materialCost)
                            NumericInputValidationHint(
                                validation: InputValidator.validate(
                                    materialCost,
                                    kind: .amount,
                                    requirement: .optionalNonNegative
                                )
                            )
                        }
                    }
                    LabeledContent(String(localized: "人工成本")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("0", text: $laborCost.numericInput(.amount))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused(focusedField, equals: .laborCost)
                            NumericInputValidationHint(
                                validation: InputValidator.validate(
                                    laborCost,
                                    kind: .amount,
                                    requirement: .optionalNonNegative
                                )
                            )
                        }
                    }
                    Picker(String(localized: "收款状态"), selection: $paymentStatus) {
                        ForEach(PaymentStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "新建工程"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "创建"), action: onCreate)
                        .disabled(!canCreate)
                        .accessibilityIdentifier("project-create-submit")
                }
                KeyboardNavigationToolbar(
                    focusedField: focusedField,
                    fields: [.contractAmount, .paidAmount, .materialCost, .laborCost]
                )
            }
        }
        .presentationDetents([.large])
    }
}

struct ProjectDocumentChecklistTemplateSection: View {
    @Binding var selectedCategories: Set<ProjectDocumentCategory>
    @Binding var recommendationStage: ProjectDocumentRecommendationStage
    let customTemplates: [ProjectDocumentChecklistTemplate]

    private var recommendedCategories: [ProjectDocumentCategory] {
        ProjectDocumentCategory.recommendedConstructionArchiveRequirements(for: recommendationStage)
    }

    var body: some View {
        Section(String(localized: "资料清单模板")) {
            LabeledContent(
                String(localized: "当前清单"),
                value: String(format: String(localized: "%lld 类"), Int64(selectedCategories.count))
            )
            templateMenu

            Picker(String(localized: "推荐阶段"), selection: $recommendationStage) {
                ForEach(ProjectDocumentRecommendationStage.allCases, id: \.self) { stage in
                    Text(stage.displayName).tag(stage)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Label(
                    String(format: String(localized: "%@推荐"), recommendationStage.displayName),
                    systemImage: "wand.and.stars"
                )
                .font(.caption.weight(.semibold))
                Text(recommendationStage.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(recommendationStage.recommendedCategoryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                selectedCategories = Set(recommendedCategories)
            } label: {
                Label(String(localized: "套用本阶段推荐"), systemImage: "checklist.checked")
            }

            ForEach(ProjectDocumentCategory.defaultConstructionArchiveRequirements, id: \.self) { category in
                Toggle(isOn: binding(for: category)) {
                    Text(category.displayName)
                }
            }
        }
    }

    private var templateMenu: some View {
        Menu {
            Section(String(localized: "项目类型")) {
                ForEach(ProjectDocumentChecklistTemplate.builtInPresets) { template in
                    Button {
                        applyTemplate(template)
                    } label: {
                        Text(template.name)
                    }
                }
            }
            if !customTemplates.isEmpty {
                Section(String(localized: "我的模板")) {
                    ForEach(customTemplates) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            Text(template.name)
                        }
                    }
                }
            }
        } label: {
            Label(String(localized: "套用项目类型模板"), systemImage: "square.stack.3d.up.fill")
        }
    }

    private func applyTemplate(_ template: ProjectDocumentChecklistTemplate) {
        selectedCategories = Set(ProjectDocumentCategory.normalizedConstructionArchiveRequirements(template.categories))
    }

    private func binding(for category: ProjectDocumentCategory) -> Binding<Bool> {
        Binding(
            get: {
                selectedCategories.contains(category)
            },
            set: { isEnabled in
                if isEnabled {
                    selectedCategories.insert(category)
                } else if selectedCategories.count > 1 {
                    selectedCategories.remove(category)
                }
            }
        )
    }
}
