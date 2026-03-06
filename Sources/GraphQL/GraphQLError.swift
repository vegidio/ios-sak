public struct GraphQLError: Decodable, Error, Sendable {
    public struct Location: Decodable, Sendable {
        public let line: Int
        public let column: Int
    }

    public let message: String
    public let locations: [Location]?
    public let path: [String]?
}
