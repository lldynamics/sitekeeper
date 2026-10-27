import Foundation

enum LinearCuttingUnit: String, CaseIterable, Identifiable {
    case millimeters = "mm"
    case meters = "m"

    var id: String { rawValue }

    var micrometersPerUnit: Int64 {
        self == .millimeters ? 1000 : 1_000_000
    }

    var fractionDigits: Int { self == .millimeters ? 3 : 6 }

    func formatted(_ micrometers: Int64) -> String {
        let value = Decimal(micrometers) / Decimal(micrometersPerUnit)
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.maximumFractionDigits = fractionDigits
        let number = formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
        return "\(number) \(rawValue)"
    }

    func converting(_ text: String, to newUnit: LinearCuttingUnit) -> String? {
        let validation = NumericInputSupport.validate(text, kind: .quantity, requirement: .optionalNonNegative)
        guard validation.isValid, let value = validation.decimalValue else { return nil }
        let micrometers = DecimalMath.multiply(value, Decimal(micrometersPerUnit))
        let converted = DecimalMath.divide(micrometers, by: Decimal(newUnit.micrometersPerUnit))
        guard !converted.isNaN else { return nil }
        return NSDecimalNumber(decimal: converted).stringValue
    }
}

struct LinearCuttingDemand: Identifiable, Equatable {
    var id = UUID()
    var lengthText = ""
    var quantityText = "1"
}

struct LinearCuttingResolvedDemand {
    let length: Int64
    let quantity: Int
}

struct LinearCuttingBar: Identifiable {
    let id: Int
    var pieceLengths: [Int64] = []
    var remaining: Int64
}

struct LinearCuttingPlan {
    let materialName: String
    let unit: LinearCuttingUnit
    let stockLength: Int64
    let kerf: Int64
    let demands: [LinearCuttingResolvedDemand]
    let bars: [LinearCuttingBar]
    let totalFinishedLength: Int64
    let totalKerfLength: Int64
    let totalRemainingLength: Int64

    var pieceCount: Int { demands.reduce(0) { $0 + $1.quantity } }
}

enum LinearCuttingError: LocalizedError {
    case missingMaterial
    case invalidLength(String)
    case unsupportedLengthPrecision
    case tooManyDemands
    case invalidQuantity(Int)
    case tooManyPieces
    case pieceDoesNotFit(Int)
    case arithmeticOverflow

    var errorDescription: String? {
        switch self {
        case .missingMaterial:
            return calculatorLoc("请填写材料名称。")
        case .invalidLength(let field):
            return calculatorLocFormat("%@无效，请填写范围内的长度。", field)
        case .unsupportedLengthPrecision:
            return calculatorLoc("长度精度最多为 0.001 mm；请调整输入，不会自动舍入长度。")
        case .tooManyDemands:
            return calculatorLoc("请填写 1–20 种段长需求。")
        case .invalidQuantity(let row):
            return calculatorLocFormat("第 %lld 种需求的数量须为 1–500 的整数。", Int64(row))
        case .tooManyPieces:
            return calculatorLoc("本次合计最多 500 段，请减少需求数量。")
        case .pieceDoesNotFit(let row):
            return calculatorLocFormat("第 %lld 种段长加切缝超过原材长度，请调整需求。", Int64(row))
        case .arithmeticOverflow:
            return calculatorLoc("计算结果超出可表示范围，请减小输入。")
        }
    }
}

enum LinearCuttingPlanner {
    static let maximumDemandCount = 20
    static let maximumPieceCount = 500
    // Exact integer micrometers: no floating-point tolerance can permit an over-cut.
    private static let maximumLengthMicrometers: Int64 = 1_000_000_000

    static func makePlan(
        materialName: String,
        stockLengthText: String,
        kerfText: String,
        unit: LinearCuttingUnit,
        demands: [LinearCuttingDemand]
    ) throws -> LinearCuttingPlan {
        let name = materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LinearCuttingError.missingMaterial }
        guard !demands.isEmpty, demands.count <= maximumDemandCount else {
            throw LinearCuttingError.tooManyDemands
        }
        let stock = try exactLength(stockLengthText, unit: unit, allowsZero: false, field: calculatorLoc("原材长度"))
        let kerf = try exactLength(kerfText, unit: unit, allowsZero: true, field: calculatorLoc("每段切缝"))
        var resolved: [LinearCuttingResolvedDemand] = []
        var pieceLengths: [Int64] = []
        for (index, demand) in demands.enumerated() {
            let length = try exactLength(
                demand.lengthText, unit: unit, allowsZero: false,
                field: calculatorLocFormat("第 %lld 种段长", Int64(index + 1))
            )
            let count = try exactCount(demand.quantityText, row: index + 1)
            guard pieceLengths.count + count <= maximumPieceCount else { throw LinearCuttingError.tooManyPieces }
            guard length + kerf <= stock else { throw LinearCuttingError.pieceDoesNotFit(index + 1) }
            resolved.append(LinearCuttingResolvedDemand(length: length, quantity: count))
            pieceLengths.append(contentsOf: repeatElement(length, count: count))
        }

        // Best-fit decreasing: longest first, then choose the tightest existing bar.
        var bars: [LinearCuttingBar] = []
        for length in pieceLengths.sorted(by: >) {
            let consumed = length + kerf
            let bestIndex = bars.indices.filter { bars[$0].remaining >= consumed }.min {
                if bars[$0].remaining == bars[$1].remaining { return $0 < $1 }
                return bars[$0].remaining < bars[$1].remaining
            }
            let targetIndex: Int
            if let bestIndex {
                targetIndex = bestIndex
            } else {
                targetIndex = bars.count
                bars.append(LinearCuttingBar(id: targetIndex + 1, remaining: stock))
            }
            bars[targetIndex].pieceLengths.append(length)
            bars[targetIndex].remaining -= consumed
        }
        // Limits above bound every total to 500 × 10^9 micrometers, within Int64.
        let finished = pieceLengths.reduce(Int64.zero, +)
        let totalKerf = Int64(pieceLengths.count) * kerf
        let remaining = bars.reduce(Int64.zero) { $0 + $1.remaining }
        guard finished + totalKerf + remaining == stock * Int64(bars.count),
              bars.allSatisfy({ $0.remaining >= 0 }) else { throw LinearCuttingError.arithmeticOverflow }
        return LinearCuttingPlan(
            materialName: name, unit: unit, stockLength: stock, kerf: kerf,
            demands: resolved, bars: bars, totalFinishedLength: finished,
            totalKerfLength: totalKerf, totalRemainingLength: remaining
        )
    }

    private static func exactLength(
        _ text: String, unit: LinearCuttingUnit, allowsZero: Bool, field: String
    ) throws -> Int64 {
        let validation = NumericInputSupport.validate(
            text, kind: .quantity, requirement: allowsZero ? .requiredNonNegative : .requiredPositive
        )
        guard validation.isValid, let decimal = validation.decimalValue else {
            throw LinearCuttingError.invalidLength(field)
        }
        var scaled = DecimalMath.multiply(decimal, Decimal(unit.micrometersPerUnit))
        guard !scaled.isNaN, scaled >= .zero, scaled <= Decimal(maximumLengthMicrometers) else {
            throw LinearCuttingError.invalidLength(field)
        }
        var integral = Decimal.zero
        NSDecimalRound(&integral, &scaled, 0, .plain)
        guard integral == scaled else { throw LinearCuttingError.unsupportedLengthPrecision }
        return NSDecimalNumber(decimal: integral).int64Value
    }

    private static func exactCount(_ text: String, row: Int) throws -> Int {
        let validation = NumericInputSupport.validate(text, kind: .quantity, requirement: .requiredPositive)
        guard validation.isValid, let decimal = validation.decimalValue,
              decimal <= Decimal(maximumPieceCount) else { throw LinearCuttingError.invalidQuantity(row) }
        let count = NSDecimalNumber(decimal: decimal).intValue
        guard Decimal(count) == decimal else { throw LinearCuttingError.invalidQuantity(row) }
        return count
    }
}
