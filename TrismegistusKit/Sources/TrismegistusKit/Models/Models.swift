import Foundation

/// A provider and one of its models, as the relay names them (`GET /api/models`, `PUT /api/sessions/{id}/model`).
public struct ModelChoice: Codable, Sendable, Hashable {
    public var provider: String
    public var model: String

    public init(provider: String, model: String) {
        self.provider = provider
        self.model = model
    }

    /// The model id with Hermes' `[1m]` (the 1M context window) shown as "1M".
    public var label: String { Self.label(model) }

    public static func label(_ id: String) -> String {
        id.replacingOccurrences(of: "[1m]", with: " 1M", options: .caseInsensitive)
    }
}

/// Hermes' connected providers and their models, plus the model a session without a choice of its own uses.
public struct ModelCatalog: Decodable, Sendable, Equatable {
    public struct Provider: Decodable, Sendable, Equatable, Identifiable {
        public var slug: String
        public var name: String
        public var models: [Model]
        public var id: String { slug }
    }

    public struct Model: Decodable, Sendable, Equatable, Identifiable {
        public var id: String
        public var reasoning: Bool?
    }

    public var current: ModelChoice
    public var providers: [Provider]

    public init(current: ModelChoice, providers: [Provider]) {
        self.current = current
        self.providers = providers
    }

    /// The connected provider offering `id`, the first when several do.
    public func choice(model id: String) -> ModelChoice? {
        providers.first { $0.models.contains { $0.id == id } }.map { ModelChoice(provider: $0.slug, model: id) }
    }

    /// The provider's display name, or its slug when it isn't connected (any more).
    public func providerName(_ slug: String) -> String {
        providers.first { $0.slug == slug }?.name ?? slug
    }
}
