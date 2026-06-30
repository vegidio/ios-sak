@testable import Components
import Testing

@Suite("Components")
struct ComponentsTests {
    @Test("Components module loads")
    func moduleLoads() {
        #expect(Bool(true))
    }
}
