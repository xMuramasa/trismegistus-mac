import Foundation
import Testing
@testable import TrismegistusKit

@Test func wireRoundTripsAValue() throws {
    let data = try Wire.encode(["b": 1, "a": 2])
    #expect(String(decoding: data, as: UTF8.self) == #"{"a":2,"b":1}"#)
    #expect(try Wire.decode([String: Int].self, from: data) == ["a": 2, "b": 1])
}
