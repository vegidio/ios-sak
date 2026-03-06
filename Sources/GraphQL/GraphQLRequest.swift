import Foundation

public struct GraphQLRequest: Sendable {
    public let query: String
    public let variables: [String: any Sendable]?
    public let operationName: String?

    public init(
        query: String,
        variables: [String: any Sendable]? = nil,
        operationName: String? = nil
    ) {
        self.query = query
        self.variables = variables
        self.operationName = operationName
    }

    func encode() throws -> Data {
        var body: [String: Any] = ["query": query]
        if let variables {
            body["variables"] = variables
        }
        if let operationName {
            body["operationName"] = operationName
        }
        return try JSONSerialization.data(withJSONObject: body)
    }
}
