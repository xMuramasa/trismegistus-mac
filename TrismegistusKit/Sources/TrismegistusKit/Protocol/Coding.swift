import Foundation

/// A coding key from a string, for hand-written Codable over the schema's snake_case fields.
struct AnyKey: CodingKey, ExpressibleByStringLiteral, Hashable {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    init(stringLiteral value: String) { stringValue = value }
}

extension KeyedDecodingContainer where Key == AnyKey {
    /// The schema's `additionalProperties: false`: fails on any key not listed.
    func only(_ keys: Set<String>) throws {
        if let extra = allKeys.first(where: { !keys.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(forKey: extra, in: self, debugDescription: "unexpected field")
        }
    }

    func check(_ ok: Bool, _ key: AnyKey, _ why: String) throws {
        if !ok { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: why) }
    }
}

/// A type whose synthesized Codable is used as is, plus the schema's `additionalProperties: false`.
protocol StrictCodable: Codable {
    associatedtype CodingKeys: CodingKey & CaseIterable
}

extension StrictCodable {
    init(strict decoder: any Decoder) throws {
        try decoder.container(keyedBy: AnyKey.self).only(Set(CodingKeys.allCases.map(\.stringValue)))
        try self.init(from: decoder)
    }
}

/// Session, run, request and client message ids: 1-128 ASCII letters, digits and `_ . : -`, the first alphanumeric.
/// Decoding doesn't check this (the relay does); RelayREST checks it before putting an id in a URL path.
public func isValidID(_ s: String) -> Bool {
    func alnum(_ c: UInt8) -> Bool { (48...57).contains(c) || (65...90).contains(c) || (97...122).contains(c) }
    let u = Array(s.utf8)
    return (1...128).contains(u.count) && alnum(u[0]) && u.allSatisfy { alnum($0) || "_.:-".utf8.contains($0) }
}

/// Arbitrary JSON: the pass-through `data` of `unknown` events.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
