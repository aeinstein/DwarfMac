import Foundation

// Minimaler Protobuf-Codec (proto3) für genau die Nachrichten, die wir mit dem
// Dwarf-Gerät austauschen. Bewusst abhängigkeitsfrei statt SwiftProtobuf+protoc,
// da die Messages sehr klein sind (Envelope + wenige Skalarfelder).
//
// Wire-Typen: 0=varint, 1=64-bit (double/fixed64), 2=length-delimited
// (bytes/string/embedded), 5=32-bit. Tag = (feldnummer << 3) | wireTyp.
// proto3 lässt Felder mit Default-/Nullwert weg.

struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
    }

    private mutating func tag(_ field: Int, _ wire: UInt8) {
        varint((UInt64(field) << 3) | UInt64(wire))
    }

    mutating func uint32(_ field: Int, _ value: UInt32) {
        guard value != 0 else { return }
        tag(field, 0); varint(UInt64(value))
    }

    mutating func int32(_ field: Int, _ value: Int32) {
        guard value != 0 else { return }
        tag(field, 0); varint(UInt64(bitPattern: Int64(value)))
    }

    mutating func uint64(_ field: Int, _ value: UInt64) {
        guard value != 0 else { return }
        tag(field, 0); varint(value)
    }

    mutating func bool(_ field: Int, _ value: Bool) {
        guard value else { return }
        tag(field, 0); varint(1)
    }

    mutating func double(_ field: Int, _ value: Double) {
        guard value != 0 else { return }
        tag(field, 1)
        let bits = value.bitPattern
        for i in 0..<8 { data.append(UInt8((bits >> (8 * i)) & 0xFF)) }
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        guard !value.isEmpty else { return }
        tag(field, 2); varint(UInt64(value.count)); data.append(value)
    }

    /// Schreibt ein eingebettetes Message-Feld — IMMER, auch wenn leer. Nötig,
    /// wenn die Feld-Präsenz selbst bedeutsam ist (z. B. ReqEnterCamera.client_param).
    mutating func message(_ field: Int, _ value: Data) {
        tag(field, 2); varint(UInt64(value.count)); data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        let b = Data(value.utf8)
        guard !b.isEmpty else { return }
        tag(field, 2); varint(UInt64(b.count)); data.append(b)
    }
}

struct ProtoReader {
    private let data: Data
    private var index: Int

    init(_ data: Data) {
        // Frische Kopie → startIndex == 0, auch wenn ein Slice übergeben wurde.
        self.data = Data(data)
        self.index = 0
    }

    var isAtEnd: Bool { index >= data.count }

    mutating func readVarint() -> UInt64? {
        var shift: UInt64 = 0
        var result: UInt64 = 0
        while index < data.count {
            let byte = data[index]; index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    mutating func readTag() -> (field: Int, wire: UInt8)? {
        guard let t = readVarint() else { return nil }
        return (Int(t >> 3), UInt8(t & 0x7))
    }

    mutating func readBytes() -> Data? {
        guard let len = readVarint() else { return nil }
        let n = Int(len)
        guard index + n <= data.count else { return nil }
        let sub = data.subdata(in: index..<index + n)
        index += n
        return sub
    }

    mutating func readDouble() -> Double? {
        guard index + 8 <= data.count else { return nil }
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(data[index + i]) << (8 * i) }
        index += 8
        return Double(bitPattern: bits)
    }

    mutating func readFixed32() -> UInt32? {
        guard index + 4 <= data.count else { return nil }
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(data[index + i]) << (8 * i) }
        index += 4
        return v
    }

    /// Prüft, ob `data` sich vollständig als gültige Protobuf-Felder lesen lässt
    /// (Heuristik zum Erkennen eingebetteter Messages beim Baum-Dump).
    static func isValidMessage(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        var reader = ProtoReader(data)
        var fields = 0
        while !reader.isAtEnd {
            guard let (field, wire) = reader.readTag(), field > 0 else { return false }
            switch wire {
            case 0: if reader.readVarint() == nil { return false }
            case 1: if reader.readDouble() == nil { return false }
            case 2: if reader.readBytes() == nil { return false }
            case 5: if reader.readFixed32() == nil { return false }
            default: return false
            }
            fields += 1
        }
        return fields > 0
    }

    /// Rekursiver, menschenlesbarer Baum-Dump einer Protobuf-Message (Diagnose).
    /// Length-delimited Felder werden als eingebettete Message erkannt (sonst
    /// String/Bytes). `#feld wire …` je Zeile, eingerückt nach Verschachtelung.
    static func debugTree(_ data: Data, indent: Int = 0) -> String {
        var reader = ProtoReader(data)
        let pad = String(repeating: "  ", count: indent)
        var out = ""
        while !reader.isAtEnd {
            guard let (field, wire) = reader.readTag() else { break }
            switch wire {
            case 0:
                let v = reader.readVarint() ?? 0
                let signed = Int64(bitPattern: v)
                out += "\(pad)#\(field) varint=\(v)\(signed < 0 ? " (\(signed))" : "")\n"
            case 1:
                out += "\(pad)#\(field) f64=\(reader.readDouble() ?? 0)\n"
            case 5:
                out += "\(pad)#\(field) f32=\(reader.readFixed32() ?? 0)\n"
            case 2:
                guard let b = reader.readBytes() else { break }
                if isValidMessage(b) {
                    out += "\(pad)#\(field) msg(\(b.count)B):\n" + debugTree(b, indent: indent + 1)
                } else if let s = String(data: b, encoding: .utf8),
                          !s.isEmpty, s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) {
                    out += "\(pad)#\(field) str=\"\(s)\"\n"
                } else {
                    out += "\(pad)#\(field) bytes=\(b.map { String(format: "%02x", $0) }.joined())\n"
                }
            default:
                reader.skip(wire)
            }
        }
        return out
    }

    mutating func skip(_ wire: UInt8) {
        switch wire {
        case 0: _ = readVarint()
        case 1: index += 8
        case 2: _ = readBytes()
        case 5: index += 4
        default: break
        }
    }

    /// Liest alle varint-Felder als (feldnummer → wert). Praktisch für die
    /// kleinen Notify-Messages (Akku, Temperatur, SD-Karte).
    static func varintFields(in data: Data) -> [Int: UInt64] {
        var reader = ProtoReader(data)
        var result: [Int: UInt64] = [:]
        while !reader.isAtEnd {
            guard let (field, wire) = reader.readTag() else { break }
            if wire == 0, let v = reader.readVarint() {
                result[field] = v
            } else {
                reader.skip(wire)
            }
        }
        return result
    }

    /// Liest alle length-delimited Felder (wire 2) als (feldnummer → [bytes]).
    /// Für eingebettete, ggf. wiederholte Messages (z. B. ResNotifyParam.param).
    static func messageFields(in data: Data) -> [Int: [Data]] {
        var reader = ProtoReader(data)
        var result: [Int: [Data]] = [:]
        while !reader.isAtEnd {
            guard let (field, wire) = reader.readTag() else { break }
            if wire == 2, let b = reader.readBytes() {
                result[field, default: []].append(b)
            } else {
                reader.skip(wire)
            }
        }
        return result
    }

    /// Liest alle 64-bit-Felder als (feldnummer → double). Für Notify-Messages
    /// mit Double-Feldern (z. B. Langzeitbelichtungs-Fortschritt).
    static func doubleFields(in data: Data) -> [Int: Double] {
        var reader = ProtoReader(data)
        var result: [Int: Double] = [:]
        while !reader.isAtEnd {
            guard let (field, wire) = reader.readTag() else { break }
            if wire == 1, let v = reader.readDouble() {
                result[field] = v
            } else {
                reader.skip(wire)
            }
        }
        return result
    }
}
