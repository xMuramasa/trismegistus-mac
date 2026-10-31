import Foundation
import Testing
@testable import TrismegistusKit

@Suite struct TokenStoreTests {
    func roundTrip(_ store: any TokenStore) throws {
        #expect(try store.token() == nil)
        try store.setToken(fakeToken)
        #expect(try store.token() == fakeToken)
        try store.setToken(fakeToken.replacingOccurrences(of: "FAKE", with: "FAKF"))
        #expect(try store.token()?.hasPrefix("trs_FAKF") == true)
        try store.deleteToken()
        #expect(try store.token() == nil)
        try store.deleteToken() // deleting nothing is fine
    }

    @Test func inMemory() throws {
        try roundTrip(InMemoryTokenStore())
    }

    #if canImport(Security)
    /// The real Keychain (login keychain: unsigned test binaries can't use the data protection one), under a
    /// throwaway service so the app's own token is never touched; removed again at the end.
    @Test func keychain() throws {
        let store = KeychainTokenStore(service: KeychainTokenStore.defaultService + ".tests",
                                       account: "test-\(UUID().uuidString)", dataProtection: false)
        defer { try? store.deleteToken() }
        do {
            try roundTrip(store)
        } catch let e as KeychainError where e.status == errSecInteractionNotAllowed {
            withKnownIssue("the login keychain is locked in this session (SSH?); run from a logged-in Terminal") { throw e }
        }
    }
    #endif
}
