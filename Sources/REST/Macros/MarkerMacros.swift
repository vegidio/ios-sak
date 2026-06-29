import SwiftSyntax
import SwiftSyntaxMacros

/// The HTTP-method and `@SkipAuth` marker macros expand to nothing. They exist only so the
/// compiler accepts the attributes on protocol requirements; `ServiceMacro` reads them from
/// the syntax tree when generating the conforming client.
private enum NoOpPeerMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

enum GetMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try NoOpPeerMacro.expansion(of: node, providingPeersOf: declaration, in: context)
    }
}

enum PostMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try NoOpPeerMacro.expansion(of: node, providingPeersOf: declaration, in: context)
    }
}

enum PutMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try NoOpPeerMacro.expansion(of: node, providingPeersOf: declaration, in: context)
    }
}

enum PatchMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try NoOpPeerMacro.expansion(of: node, providingPeersOf: declaration, in: context)
    }
}

enum DeleteMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try NoOpPeerMacro.expansion(of: node, providingPeersOf: declaration, in: context)
    }
}

enum SkipAuthMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try NoOpPeerMacro.expansion(of: node, providingPeersOf: declaration, in: context)
    }
}
