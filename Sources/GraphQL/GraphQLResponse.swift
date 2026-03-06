public struct GraphQLResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let data: T?
    public let errors: [GraphQLError]?

    public var hasErrors: Bool { !(errors?.isEmpty ?? true) }
}
