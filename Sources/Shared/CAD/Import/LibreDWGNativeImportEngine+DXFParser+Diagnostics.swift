import Foundation

extension DXFBasic2DParser {
    static func unsupportedRecord(
        type: String,
        pairs: [Pair],
        code: String,
        reason: String
    ) -> EntityRecord {
        EntityRecord(
            kind: .unsupported,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: nil,
            text: nil,
            bounds: .empty,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: type,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: code,
                    message: reason,
                    detail: firstString(code: 5, in: pairs)
                )
            ],
            unsupportedReason: reason
        )
    }


    static func firstInt(code: Int, in pairs: [Pair]) -> Int? {
        guard let value = pairs.first(where: { $0.code == code })?.value else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }


    static func firstDouble(code: Int, in pairs: [Pair]) -> Double? {
        guard let value = pairs.first(where: { $0.code == code })?.value else { return nil }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }


    static func allDoubles(code: Int, in pairs: [Pair]) -> [Double] {
        pairs.compactMap { pair in
            guard pair.code == code else { return nil }
            return Double(pair.value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }


    static func positiveOrNil(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }


    static func lineWeight(from pairs: [Pair]) -> Double? {
        guard let raw = firstInt(code: 370, in: pairs), raw >= 0 else { return nil }
        return Double(raw) / 100
    }


    static func lineType(from pairs: [Pair]) -> String? {
        let value = firstString(code: 6, in: pairs)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }


    static func colorARGB(from pairs: [Pair], defaultACI: Int?) -> UInt32? {
        if let trueColor = firstInt(code: 420, in: pairs), trueColor > 0 {
            return 0xFF000000 | UInt32(trueColor & 0x00FF_FFFF)
        }
        if let aci = firstInt(code: 62, in: pairs) {
            if aci == 0 || abs(aci) == 256 {
                return nil
            }
            return aciToARGB(abs(aci))
        }
        if let defaultACI {
            return aciToARGB(abs(defaultACI))
        }
        return nil
    }


    static func aciToARGB(_ index: Int) -> UInt32 {
        switch index {
        case 1:
            return 0xFFFF0000
        case 2:
            return 0xFFFFFF00
        case 3:
            return 0xFF00FF00
        case 4:
            return 0xFF00FFFF
        case 5:
            return 0xFF0000FF
        case 6:
            return 0xFFFF00FF
        case 7:
            return 0xFF2F3437
        case 8:
            return 0xFF808080
        case 9:
            return 0xFFC0C0C0
        default:
            let normalized = Double((index - 1) % 24) / 24
            let hue = normalized * 6
            let c = 1.0
            let x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
            let rgb: (Double, Double, Double)
            switch hue {
            case 0..<1: rgb = (c, x, 0)
            case 1..<2: rgb = (x, c, 0)
            case 2..<3: rgb = (0, c, x)
            case 3..<4: rgb = (0, x, c)
            case 4..<5: rgb = (x, 0, c)
            default: rgb = (c, 0, x)
            }
            let r = UInt32(max(0, min(255, Int(rgb.0 * 255))))
            let g = UInt32(max(0, min(255, Int(rgb.1 * 255))))
            let b = UInt32(max(0, min(255, Int(rgb.2 * 255))))
            return 0xFF000000 | (r << 16) | (g << 8) | b
        }
    }


    static func visibility(from pairs: [Pair]) -> Kernel.CADVisibility {
        if (firstInt(code: 60, in: pairs) ?? 0) == 1 {
            return .hidden
        }
        if let aci = firstInt(code: 62, in: pairs), aci < 0 {
            return .hidden
        }
        return .visible
    }


    static func firstString(code: Int, in pairs: [Pair]) -> String? {
        pairs.first(where: { $0.code == code })?.value
    }


    static func joinedText(from pairs: [Pair], acceptedCodes: Set<Int>) -> String {
        pairs
            .filter { acceptedCodes.contains($0.code) }
            .map(\.value)
            .joined()
    }


    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
