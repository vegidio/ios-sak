import Foundation
import SwiftBasicFormat
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Generates a concrete `<Protocol>Client` struct that implements a `@Service`-annotated protocol.
///
/// For every requirement it reads the HTTP-method annotation (`@Get`/`@Post`/…), the optional
/// `@SkipAuth` marker, and each parameter's marker type (`Path`/`Query`/`Body`/`Header`), then
/// emits a method body that builds a `RESTRequest` and forwards it to `client.send(_:)`.
public enum ServiceMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(.error("@Service can only be applied to a protocol", at: node))
            return []
        }

        let access = accessModifier(of: protocolDecl)
        let protocolName = protocolDecl.name.text

        var methods: [String] = []
        for member in protocolDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            if let method = makeMethod(funcDecl, access: access, context: context) {
                methods.append(method)
            }
        }

        // Built left-aligned; SwiftBasicFormat re-indents the whole declaration deterministically.
        let source = """
        \(access)struct \(protocolName)Client: \(protocolName) {
        private let client: RESTClient
        \(access)init(
        baseURL: String,
        defaultHeaders: [String: String] = [:],
        retryPolicy: RetryPolicy? = RetryPolicy(),
        cachePolicy: CachePolicy? = nil,
        tokenExpiryDate: (@Sendable () -> Date?)? = nil,
        preemptiveRefreshLeadTime: TimeInterval = 60,
        isUnauthorized: (@Sendable (HTTPURLResponse) -> Bool)? = nil,
        refreshToken: (@Sendable () async throws -> String)? = nil,
        applyToken: (@Sendable (String, inout URLRequest) -> Void)? = nil,
        getToken: (@Sendable () -> String?)? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        sessionConfiguration: URLSessionConfiguration? = nil
        ) {
        self.client = RESTClient(
        baseURL: baseURL,
        defaultHeaders: defaultHeaders,
        retryPolicy: retryPolicy,
        cachePolicy: cachePolicy,
        tokenExpiryDate: tokenExpiryDate,
        preemptiveRefreshLeadTime: preemptiveRefreshLeadTime,
        isUnauthorized: isUnauthorized,
        refreshToken: refreshToken,
        applyToken: applyToken,
        getToken: getToken,
        decoder: decoder,
        sessionConfiguration: sessionConfiguration
        )
        }
        \(methods.joined(separator: "\n"))
        }
        """

        let structDecl = DeclSyntax(stringLiteral: source)
        let formatted = structDecl.formatted(using: BasicFormat(indentationWidth: .spaces(4)))
        return [DeclSyntax(formatted.cast(StructDeclSyntax.self))]
    }

    // MARK: - Method generation

    private enum ParamKind { case path, query, body, header }

    private struct ParsedParam {
        let label: String          // external argument label as written (may be "_")
        let name: String           // internal name used in the body / as wire key
        let innerType: String      // type with the marker unwrapped
        let kind: ParamKind
    }

    private static func makeMethod(
        _ funcDecl: FunctionDeclSyntax,
        access: String,
        context: some MacroExpansionContext
    ) -> String? {
        let funcName = funcDecl.name.text

        // HTTP method + path
        guard let (httpMethod, path) = httpMethod(of: funcDecl) else {
            context.diagnose(.error(
                "'\(funcName)' must be annotated with one of @Get, @Post, @Put, @Patch or @Delete",
                at: funcDecl
            ))
            return nil
        }

        // async throws + return type
        let effects = funcDecl.signature.effectSpecifiers
        guard effects?.asyncSpecifier != nil, effects?.throwsClause != nil else {
            context.diagnose(.error("'\(funcName)' must be declared 'async throws'", at: funcDecl))
            return nil
        }
        guard let returnType = funcDecl.signature.returnClause?.type.trimmedDescription else {
            context.diagnose(.error("'\(funcName)' must return RESTResponse<T>", at: funcDecl))
            return nil
        }

        // Parameters
        var params: [ParsedParam] = []
        for param in funcDecl.signature.parameterClause.parameters {
            let label = param.firstName.text
            let name = param.secondName?.text ?? param.firstName.text
            guard let (kind, inner) = marker(of: param.type) else {
                context.diagnose(.error(
                    "Parameter '\(name)' must be marked with Path, Query, Body or Header",
                    at: param
                ))
                return nil
            }
            params.append(ParsedParam(label: label, name: name, innerType: inner, kind: kind))
        }

        let bodyParams = params.filter { $0.kind == .body }
        guard bodyParams.count <= 1 else {
            context.diagnose(.error("'\(funcName)' has more than one Body parameter", at: funcDecl))
            return nil
        }

        // Validate path placeholders against Path params
        let placeholders = self.placeholders(in: path)
        let pathParamNames = Set(params.filter { $0.kind == .path }.map(\.name))
        for placeholder in placeholders where !pathParamNames.contains(placeholder) {
            context.diagnose(.error(
                "Path placeholder '{\(placeholder)}' has no matching Path parameter",
                at: funcDecl
            ))
            return nil
        }
        for pathParam in pathParamNames where !placeholders.contains(pathParam) {
            context.diagnose(.error(
                "Path parameter '\(pathParam)' is not used in the path '\(path)'",
                at: funcDecl
            ))
            return nil
        }

        // Build the URL string literal, substituting {name} -> \(name)
        var urlContent = path
        for name in pathParamNames {
            urlContent = urlContent.replacingOccurrences(of: "{\(name)}", with: "\\(\(name))")
        }

        // Signature
        let signatureParams = params.map { p -> String in
            if p.label == p.name {
                return "\(p.name): \(p.innerType)"
            } else {
                return "\(p.label) \(p.name): \(p.innerType)"
            }
        }.joined(separator: ", ")

        // RESTRequest arguments
        let hasBody = !bodyParams.isEmpty
        var args = ["url: \"\(urlContent)\"", "method: .\(httpMethod)"]

        let headerParams = params.filter { $0.kind == .header }
        if !headerParams.isEmpty {
            let entries = headerParams.map { "\"\($0.name)\": \"\\(\($0.name))\"" }.joined(separator: ", ")
            args.append("headers: [\(entries)]")
        }
        if let bodyParam = bodyParams.first {
            args.append("body: \(bodyParam.name)")
        }
        let queryParams = params.filter { $0.kind == .query }
        if !queryParams.isEmpty {
            let entries = queryParams.map { "\"\($0.name)\": \"\\(\($0.name))\"" }.joined(separator: ", ")
            args.append("queryParameters: [\(entries)]")
        }
        if hasSkipAuth(funcDecl) {
            args.append("skipAuth: true")
        }

        let requestExpr = "\(hasBody ? "try " : "")RESTRequest(\n\(args.joined(separator: ",\n"))\n)"

        return """
        \(access)func \(funcName)(\(signatureParams)) async throws -> \(returnType) {
        let request = \(requestExpr)
        return try await client.send(request)
        }
        """
    }

    // MARK: - Parsing helpers

    /// Returns the access-control modifier (with a trailing space) to mirror on the generated
    /// client, e.g. `"public "`, `"private "`, or `""` for the default internal access.
    private static func accessModifier(of protocolDecl: ProtocolDeclSyntax) -> String {
        let accessKeywords: Set<TokenKind> = [
            .keyword(.public), .keyword(.package), .keyword(.internal),
            .keyword(.fileprivate), .keyword(.private),
        ]
        guard let modifier = protocolDecl.modifiers.first(where: { accessKeywords.contains($0.name.tokenKind) }) else {
            return ""
        }
        // `private` members would be inaccessible to the rest of the file (and couldn't satisfy
        // the conformance), so widen it to `fileprivate`, which is the effective scope of a
        // `private` top-level protocol anyway.
        let keyword = modifier.name.tokenKind == .keyword(.private) ? "fileprivate" : modifier.name.text
        return "\(keyword) "
    }

    private static let methodMap: [String: String] = [
        "Get": "get", "Post": "post", "Put": "put", "Patch": "patch", "Delete": "delete",
    ]

    private static func httpMethod(of funcDecl: FunctionDeclSyntax) -> (method: String, path: String)? {
        for attribute in funcDecl.attributes {
            guard let attr = attribute.as(AttributeSyntax.self),
                  let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
                  let method = methodMap[name] else { continue }
            let path = stringLiteralValue(attr.arguments) ?? ""
            return (method, path)
        }
        return nil
    }

    private static func hasSkipAuth(_ funcDecl: FunctionDeclSyntax) -> Bool {
        funcDecl.attributes.contains { attribute in
            attribute.as(AttributeSyntax.self)?
                .attributeName.as(IdentifierTypeSyntax.self)?.name.text == "SkipAuth"
        }
    }

    private static func marker(of type: TypeSyntax) -> (kind: ParamKind, inner: String)? {
        guard let idType = type.as(IdentifierTypeSyntax.self),
              let generic = idType.genericArgumentClause else { return nil }
        let inner = generic.arguments.trimmedDescription
        switch idType.name.text {
        case "Path": return (.path, inner)
        case "Query": return (.query, inner)
        case "Body": return (.body, inner)
        case "Header": return (.header, inner)
        default: return nil
        }
    }

    private static func stringLiteralValue(_ arguments: AttributeSyntax.Arguments?) -> String? {
        guard let list = arguments?.as(LabeledExprListSyntax.self),
              let expr = list.first?.expression.as(StringLiteralExprSyntax.self) else { return nil }
        return expr.segments.compactMap { segment in
            segment.as(StringSegmentSyntax.self)?.content.text
        }.joined()
    }

    private static func placeholders(in path: String) -> Set<String> {
        var result: Set<String> = []
        var current = ""
        var inside = false
        for char in path {
            if char == "{" {
                inside = true
                current = ""
            } else if char == "}" {
                if inside, !current.isEmpty { result.insert(current) }
                inside = false
            } else if inside {
                current.append(char)
            }
        }
        return result
    }
}

// MARK: - Diagnostics

private struct RESTMacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "RESTMacros", id: "ServiceMacro")
        self.severity = .error
    }
}

private extension Diagnostic {
    static func error(_ message: String, at node: some SyntaxProtocol) -> Diagnostic {
        Diagnostic(node: node, message: RESTMacroDiagnostic(message))
    }
}
