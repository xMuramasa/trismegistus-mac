import Foundation

/// What the pairing sheet extracts from a pasted one-time code or the QR payload.
public struct PairingPayload: Sendable, Equatable {
    /// `XXXX-XXXX-XXXX`, upper case.
    public var code: String
    /// Present when the input was the QR payload; always https.
    public var relayURL: URL?

    public enum Failure: Error, Sendable, Equatable, LocalizedError {
        case empty
        /// Not 12 Crockford base32 characters.
        case malformedCode
        /// Not `{"v":1,"url":...,"code":...}`, or a version this app does not know.
        case malformedPayload
        case malformedURL
        case insecureURL

        public var errorDescription: String? {
            switch self {
            case .empty: "Paste the pairing code first."
            case .malformedCode: "That is not a pairing code. It looks like XXXX-XXXX-XXXX."
            case .malformedPayload: "That QR payload is not recognized."
            case .malformedURL: "The relay address in the payload is not a valid URL."
            case .insecureURL: "The relay address must start with https://."
            }
        }
    }

    public static func parse(_ input: String) throws(Failure) -> PairingPayload {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }
        guard text.hasPrefix("{") else { return PairingPayload(code: try normalize(text), relayURL: nil) }

        guard let p = try? JSONDecoder().decode(QRPayload.self, from: Data(text.utf8)), p.v == 1 else { throw .malformedPayload }
        let code = try normalize(p.code)
        guard let raw = p.url else { return PairingPayload(code: code, relayURL: nil) }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), url.host?.isEmpty == false else { throw .malformedURL }
        guard scheme == "https" else { throw .insecureURL }
        return PairingPayload(code: code, relayURL: url)
    }

    /// Crockford base32: case-insensitive, I and L read as 1, O as 0, separators ignored, no U.
    static func normalize(_ raw: String) throws(Failure) -> String {
        var chars: [Character] = []
        for c in raw.uppercased() where !c.isWhitespace && c != "-" {
            switch c {
            case "I", "L": chars.append("1")
            case "O": chars.append("0")
            default:
                guard c.isASCII, c.isLetter || c.isNumber, c != "U" else { throw .malformedCode }
                chars.append(c)
            }
        }
        guard chars.count == 12 else { throw .malformedCode }
        let s = String(chars)
        return "\(s.prefix(4))-\(s.dropFirst(4).prefix(4))-\(s.suffix(4))"
    }
}

private struct QRPayload: Decodable {
    var v: Int
    var url: String?
    var code: String
}
