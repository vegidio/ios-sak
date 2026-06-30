import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct RESTMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ServiceMacro.self,
        GetMacro.self,
        PostMacro.self,
        PutMacro.self,
        PatchMacro.self,
        DeleteMacro.self,
        SkipAuthMacro.self,
        CacheableMacro.self,
        NoCacheMacro.self,
    ]
}
