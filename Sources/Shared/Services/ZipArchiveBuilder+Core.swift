import Foundation

struct DOSDateTime {
    let date: UInt16
    let time: UInt16

    static func now() -> DOSDateTime {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let year = max(1980, comps.year ?? 1980)
        let month = max(1, min(12, comps.month ?? 1))
        let day = max(1, min(31, comps.day ?? 1))
        let hour = max(0, min(23, comps.hour ?? 0))
        let minute = max(0, min(59, comps.minute ?? 0))
        let second = max(0, min(59, comps.second ?? 0))
        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        let dosTime = UInt16(hour << 11 | minute << 5 | second / 2)
        return DOSDateTime(date: dosDate, time: dosTime)
    }
}

enum CRC32 {
    static func calculate(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                if (value & 1) != 0 {
                    value = (value >> 1) ^ 0xEDB8_8320
                } else {
                    value >>= 1
                }
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendLE(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { buffer in
            append(contentsOf: buffer)
        }
    }

    mutating func appendLE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { buffer in
            append(contentsOf: buffer)
        }
    }

    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        let i0 = index(startIndex, offsetBy: offset)
        let i1 = index(after: i0)
        return UInt16(self[i0]) | (UInt16(self[i1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        let i0 = index(startIndex, offsetBy: offset)
        let i1 = index(after: i0)
        let i2 = index(after: i1)
        let i3 = index(after: i2)
        return UInt32(self[i0])
            | (UInt32(self[i1]) << 8)
            | (UInt32(self[i2]) << 16)
            | (UInt32(self[i3]) << 24)
    }

    func uint64LE(at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        var value: UInt64 = 0
        for indexOffset in 0..<8 {
            let i = index(startIndex, offsetBy: offset + indexOffset)
            value |= UInt64(self[i]) << UInt64(indexOffset * 8)
        }
        return value
    }

    func slice(from offset: Int, count length: Int) -> Data {
        let start = index(startIndex, offsetBy: offset)
        let end = index(start, offsetBy: length)
        return Data(self[start..<end])
    }
}
