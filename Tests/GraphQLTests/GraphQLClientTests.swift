import Testing
@testable import GraphQL

@Suite("GraphQLClient")
struct GraphQLClientTests {
    @Test("GraphQLRequest encodes query")
    func requestEncodesQuery() throws {
        let request = GraphQLRequest(query: "{ users { id name } }")
        let data = try request.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["query"] as? String == "{ users { id name } }")
    }

    @Test("GraphQLRequest encodes variables")
    func requestEncodesVariables() throws {
        let request = GraphQLRequest(query: "query($id: ID!) { user(id: $id) { name } }", variables: ["id": "42"])
        let data = try request.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let variables = json?["variables"] as? [String: Any]
        #expect(variables?["id"] as? String == "42")
    }

    @Test("GraphQLResponse detects errors")
    func responseDetectsErrors() throws {
        let json = """
        {"data": null, "errors": [{"message": "Not found"}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(GraphQLResponse<String?>.self, from: json)
        #expect(response.hasErrors == true)
        #expect(response.errors?.first?.message == "Not found")
    }
}
