import Testing
@testable import REST

@Suite("RESTRequest")
struct RESTRequestTests {
    @Test("HTTPMethod raw values")
    func httpMethodRawValues() {
        #expect(HTTPMethod.get.rawValue == "GET")
        #expect(HTTPMethod.post.rawValue == "POST")
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.patch.rawValue == "PATCH")
        #expect(HTTPMethod.delete.rawValue == "DELETE")
    }

    @Test("RESTRequest builds URL with query parameters")
    func requestBuildsURLWithQueryParams() throws {
        let request = RESTRequest(
            url: "https://api.example.com/users",
            method: .get,
            queryParameters: ["page": "1", "limit": "20"]
        )
        let urlRequest = try request.buildURLRequest()
        let urlString = urlRequest.url?.absoluteString ?? ""
        #expect(urlString.contains("page=1") || urlString.contains("page=1"))
        #expect(urlString.contains("limit=20"))
    }

    @Test("RESTRequest throws on invalid URL")
    func requestThrowsOnInvalidURL() {
        let request = RESTRequest(url: "not a valid url ://", method: .get)
        #expect(throws: RESTError.invalidURL) {
            try request.buildURLRequest()
        }
    }
}
