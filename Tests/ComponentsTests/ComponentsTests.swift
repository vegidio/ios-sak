import Testing
@testable import Components

@Suite("Components")
struct ComponentsTests {
    @Test("Components module loads")
    func moduleLoads() {
        #expect(Bool(true))
    }
}
