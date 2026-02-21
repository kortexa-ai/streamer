import Foundation

// Minimal msgpack encoder/decoder for fal.ai realtime protocol

enum MsgPack {

    static func encode(_ value: Any) -> Data {
        var data = Data()
        encodeValue(value, into: &data)
        return data
    }

    static func decode(_ data: Data) -> Any? {
        var offset = 0
        return decodeValue(data, offset: &offset)
    }

    // MARK: - Encoder

    private static func encodeValue(_ value: Any, into data: inout Data) {
        if let dict = value as? [String: Any] {
            let count = dict.count
            if count < 16 {
                data.append(UInt8(0x80 | count))
            } else {
                data.append(0xde)
                data.append(UInt8((count >> 8) & 0xff))
                data.append(UInt8(count & 0xff))
            }
            for (k, v) in dict {
                encodeValue(k, into: &data)
                encodeValue(v, into: &data)
            }
        } else if let str = value as? String {
            let bytes = Array(str.utf8)
            let len = bytes.count
            if len < 32 {
                data.append(UInt8(0xa0 | len))
            } else if len < 256 {
                data.append(0xd9)
                data.append(UInt8(len))
            } else if len < 65536 {
                data.append(0xda)
                data.append(UInt8((len >> 8) & 0xff))
                data.append(UInt8(len & 0xff))
            } else {
                data.append(0xdb)
                data.append(UInt8((len >> 24) & 0xff))
                data.append(UInt8((len >> 16) & 0xff))
                data.append(UInt8((len >> 8) & 0xff))
                data.append(UInt8(len & 0xff))
            }
            data.append(contentsOf: bytes)
        } else if let num = value as? Int {
            if num >= 0 && num < 128 {
                data.append(UInt8(num))
            } else if num >= 0 && num < 256 {
                data.append(0xcc)
                data.append(UInt8(num))
            } else if num >= 0 && num < 65536 {
                data.append(0xcd)
                data.append(UInt8((num >> 8) & 0xff))
                data.append(UInt8(num & 0xff))
            } else {
                data.append(0xce)
                data.append(UInt8((num >> 24) & 0xff))
                data.append(UInt8((num >> 16) & 0xff))
                data.append(UInt8((num >> 8) & 0xff))
                data.append(UInt8(num & 0xff))
            }
        } else if let arr = value as? [Any] {
            let count = arr.count
            if count < 16 {
                data.append(UInt8(0x90 | count))
            } else {
                data.append(0xdc)
                data.append(UInt8((count >> 8) & 0xff))
                data.append(UInt8(count & 0xff))
            }
            for item in arr { encodeValue(item, into: &data) }
        } else if let b = value as? Bool {
            data.append(b ? 0xc3 : 0xc2)
        } else {
            data.append(0xc0) // nil
        }
    }

    // MARK: - Decoder

    private static func decodeValue(_ data: Data, offset: inout Int) -> Any? {
        guard offset < data.count else { return nil }
        let byte = data[offset]
        offset += 1

        // positive fixint (0x00-0x7f)
        if byte < 0x80 { return Int(byte) }
        // fixmap (0x80-0x8f)
        if byte <= 0x8f { return decodeMap(data, count: Int(byte & 0x0f), offset: &offset) }
        // fixarray (0x90-0x9f)
        if byte <= 0x9f { return decodeArray(data, count: Int(byte & 0x0f), offset: &offset) }
        // fixstr (0xa0-0xbf)
        if byte <= 0xbf { return decodeString(data, count: Int(byte & 0x1f), offset: &offset) }

        switch byte {
        case 0xc0: return nil // nil
        case 0xc2: return false
        case 0xc3: return true
        // bin8, bin16, bin32
        case 0xc4: let n = Int(data[offset]); offset += 1; return decodeBin(data, count: n, offset: &offset)
        case 0xc5: let n = readUInt16(data, offset: &offset); return decodeBin(data, count: n, offset: &offset)
        case 0xc6: let n = readUInt32(data, offset: &offset); return decodeBin(data, count: n, offset: &offset)
        // float32, float64
        case 0xca:
            let bits = UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 | UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])
            offset += 4; return Float(bitPattern: bits)
        case 0xcb:
            var bits: UInt64 = 0
            for i in 0..<8 { bits = bits << 8 | UInt64(data[offset+i]) }
            offset += 8; return Double(bitPattern: bits)
        // uint8, uint16, uint32
        case 0xcc: let v = Int(data[offset]); offset += 1; return v
        case 0xcd: return readUInt16(data, offset: &offset)
        case 0xce: return readUInt32(data, offset: &offset)
        // int8, int16, int32
        case 0xd0: let v = Int(Int8(bitPattern: data[offset])); offset += 1; return v
        case 0xd1: let v = Int(Int16(bitPattern: UInt16(data[offset]) << 8 | UInt16(data[offset+1]))); offset += 2; return v
        case 0xd2:
            let v = Int(Int32(bitPattern: UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 | UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])))
            offset += 4; return v
        // str8, str16, str32
        case 0xd9: let n = Int(data[offset]); offset += 1; return decodeString(data, count: n, offset: &offset)
        case 0xda: let n = readUInt16(data, offset: &offset); return decodeString(data, count: n, offset: &offset)
        case 0xdb: let n = readUInt32(data, offset: &offset); return decodeString(data, count: n, offset: &offset)
        // array16
        case 0xdc: let n = readUInt16(data, offset: &offset); return decodeArray(data, count: n, offset: &offset)
        // map16
        case 0xde: let n = readUInt16(data, offset: &offset); return decodeMap(data, count: n, offset: &offset)
        default:
            // negative fixint (0xe0-0xff)
            if byte >= 0xe0 { return Int(Int8(bitPattern: byte)) }
            return nil
        }
    }

    private static func readUInt16(_ data: Data, offset: inout Int) -> Int {
        let v = Int(data[offset]) << 8 | Int(data[offset+1]); offset += 2; return v
    }

    private static func readUInt32(_ data: Data, offset: inout Int) -> Int {
        let v = Int(data[offset]) << 24 | Int(data[offset+1]) << 16 | Int(data[offset+2]) << 8 | Int(data[offset+3]); offset += 4; return v
    }

    private static func decodeMap(_ data: Data, count: Int, offset: inout Int) -> [String: Any] {
        var dict = [String: Any]()
        for _ in 0..<count {
            if let key = decodeValue(data, offset: &offset) as? String,
               let val = decodeValue(data, offset: &offset) { dict[key] = val }
        }
        return dict
    }

    private static func decodeArray(_ data: Data, count: Int, offset: inout Int) -> [Any] {
        var arr = [Any]()
        for _ in 0..<count { if let v = decodeValue(data, offset: &offset) { arr.append(v) } }
        return arr
    }

    private static func decodeString(_ data: Data, count: Int, offset: inout Int) -> String {
        let str = String(data: data[offset..<offset+count], encoding: .utf8) ?? ""
        offset += count; return str
    }

    private static func decodeBin(_ data: Data, count: Int, offset: inout Int) -> Data {
        let bin = Data(data[offset..<offset+count])
        offset += count; return bin
    }
}
