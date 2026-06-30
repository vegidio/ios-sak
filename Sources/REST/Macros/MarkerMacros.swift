import SwiftSyntax
import SwiftSyntaxMacros

/// The HTTP-method, `@SkipAuth`, `@Cacheable` and `@NoCache` marker macros expand to nothing.
/// They exist only so the compiler accepts the attributes on protocol requirements;
/// `ServiceMacro` reads them from the syntax tree when generating the conforming client. Each
/// must be a distinct type because `RESTMacrosPlugin` registers them by name; the empty
/// expansion is shared here.
protocol NoOpPeerMacro: PeerMacro {}

extension NoOpPeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

enum GetMacro: NoOpPeerMacro {}
enum PostMacro: NoOpPeerMacro {}
enum PutMacro: NoOpPeerMacro {}
enum PatchMacro: NoOpPeerMacro {}
enum DeleteMacro: NoOpPeerMacro {}
enum SkipAuthMacro: NoOpPeerMacro {}
enum CacheableMacro: NoOpPeerMacro {}
enum NoCacheMacro: NoOpPeerMacro {}
