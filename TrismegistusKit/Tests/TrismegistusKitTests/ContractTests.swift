import Foundation
import Testing
@testable import TrismegistusKit

/// The repo's protocol/ dir, found by walking up from this file, so tests see examples added after they were written.
let protocolDir: URL? = {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while dir.path != "/" {
        dir = dir.deletingLastPathComponent()
        let p = dir.appendingPathComponent("protocol")
        if FileManager.default.fileExists(atPath: p.appendingPathComponent("schema.json").path) { return p }
    }
    return nil
}()

func exampleFiles(_ kind: String) -> [String] {
    guard let dir = protocolDir?.appendingPathComponent("examples/\(kind)"),
          let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
    return names.filter { $0.hasSuffix(".json") }.sorted()
}

func example(_ kind: String, _ name: String) throws -> Data {
    try Data(contentsOf: try #require(protocolDir).appendingPathComponent("examples/\(kind)/\(name)"))
}

/// `<file>  <constraint>` lines of Resources/relay-enforced.txt.
let relayEnforced: [String: String] = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/relay-enforced.txt")
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    var out: [String: String] = [:]
    for line in text.split(separator: "\n") where !line.hasPrefix("#") {
        let parts = line.split(separator: " ", maxSplits: 1)
        out[String(parts[0])] = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
    }
    return out
}()

let clientTypes: Set = ["auth", "subscribe", "unsubscribe", "prompt", "stop", "steer", "approve", "ping"]

/// Runs a script in the repo's scripts/ dir and returns its stdout.
func runScript(_ name: String, _ args: [String]) throws -> String {
    let script = try #require(protocolDir).deletingLastPathComponent().appendingPathComponent("scripts/\(name)")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [script.path] + args
    let out = Pipe()
    p.standardOutput = out
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    #expect(p.terminationStatus == 0)
    return String(decoding: data, as: UTF8.self)
}

let ownerProtocolDir: String? = {
    let dir = ProcessInfo.processInfo.environment["TRISMEGISTUS_PROTOCOL_DIR"] ?? "/home/muramasa/Projects/hermes-relay/protocol"
    return FileManager.default.fileExists(atPath: dir + "/schema.json") ? dir : nil
}()

@Suite struct ContractTests {
    @Test func examplesExist() throws {
        _ = try #require(protocolDir, "protocol/ not found above \(#filePath)")
        #expect(!exampleFiles("valid").isEmpty)
        #expect(!exampleFiles("invalid").isEmpty)
    }

    /// Decodes as the message type its name starts with, and decode -> encode -> decode gives the same value and
    /// the same JSON (compared as values, not bytes).
    @Test(arguments: exampleFiles("valid"))
    func validExampleRoundTrips(_ name: String) throws {
        let data = try example("valid", name)
        let type = try #require(name.split(separator: "-").first.map { String($0.replacingOccurrences(of: ".json", with: "")) })
        let original = try Wire.decode(JSONValue.self, from: data)
        let encoded: Data
        if clientTypes.contains(type) {
            let msg = try Wire.decode(ClientMessage.self, from: data)
            #expect(msg.type == type)
            encoded = try Wire.encode(msg)
            #expect(try Wire.decode(ClientMessage.self, from: encoded) == msg)
        } else {
            let msg = try Wire.decode(ServerMessage.self, from: data)
            #expect(msg.type == type)
            encoded = try Wire.encode(msg)
            #expect(try Wire.decode(ServerMessage.self, from: encoded) == msg)
        }
        #expect(try Wire.decode(JSONValue.self, from: encoded) == original)
    }

    /// Rejected by both message enums, or listed as a rule only the relay checks.
    @Test(arguments: exampleFiles("invalid"))
    func invalidExampleIsRejected(_ name: String) throws {
        let data = try example("invalid", name)
        let decodes = (try? Wire.decode(ClientMessage.self, from: data)) != nil
            || (try? Wire.decode(ServerMessage.self, from: data)) != nil
        if let rule = relayEnforced[name] {
            #expect(decodes, "\(name) is rejected in Swift now; drop it from relay-enforced.txt")
            #expect(!rule.isEmpty, "\(name) needs the constraint the relay enforces")
        } else {
            #expect(!decodes, "\(name) decodes; reject it in the Swift types or list it in relay-enforced.txt")
        }
    }

    @Test func relayEnforcedListsOnlyExistingExamples() {
        let invalid = Set(exampleFiles("invalid"))
        for name in relayEnforced.keys {
            #expect(invalid.contains(name), "relay-enforced.txt lists \(name), which is not in examples/invalid")
        }
    }

    /// protocol/SOURCE is what scripts/protocol-hash.sh printed at the last sync; editing the copy breaks this.
    @Test func copyMatchesSource() throws {
        let source = try String(contentsOf: try #require(protocolDir).appendingPathComponent("SOURCE"), encoding: .utf8)
        #expect(try runScript("protocol-hash.sh", []) == source, "protocol/ changed without scripts/sync-protocol.sh")
    }

    @Test(.enabled(if: ownerProtocolDir != nil, "no trismegistus checkout; set TRISMEGISTUS_PROTOCOL_DIR to compare"))
    func copyMatchesOwner() throws {
        let owner = try runScript("protocol-hash.sh", [try #require(ownerProtocolDir)])
        #expect(try runScript("protocol-hash.sh", []) == owner, "the trismegistus protocol moved on; run scripts/sync-protocol.sh")
    }

    @Test func alwaysCannotBeSentOrDecoded() throws {
        #expect(ApprovalChoice(rawValue: "always") == nil)
        #expect(!ApprovalChoice.allCases.map(\.rawValue).contains("always"))
        let approve = ClientMessage.approve(runID: "run_1", requestID: "req_1", choice: .session)
        #expect(String(decoding: try Wire.encode(approve), as: UTF8.self)
            == #"{"choice":"session","request_id":"req_1","run_id":"run_1","type":"approve"}"#)
    }
}
