@testable import REST
import Testing

@Suite("RESTClient.resolveURL")
struct BaseURLResolutionTests {
    @Test("relative path is joined to the base URL")
    func relativeJoined() {
        let resolved = RESTClient.resolveURL("users/7", baseURL: "https://api.example.com")
        #expect(resolved == "https://api.example.com/users/7")
    }

    @Test("duplicate slashes at the seam are collapsed")
    func collapsesSlashes() {
        let resolved = RESTClient.resolveURL("/users", baseURL: "https://api.example.com/")
        #expect(resolved == "https://api.example.com/users")
    }

    @Test("absolute URL is returned unchanged")
    func absoluteUnchanged() {
        let resolved = RESTClient.resolveURL("https://other.example.com/x", baseURL: "https://api.example.com")
        #expect(resolved == "https://other.example.com/x")
    }

    @Test("nil base URL leaves the path unchanged")
    func nilBase() {
        let resolved = RESTClient.resolveURL("users", baseURL: nil)
        #expect(resolved == "users")
    }
}
