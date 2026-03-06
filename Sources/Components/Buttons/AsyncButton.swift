import SwiftUI

public struct AsyncButton<Label: View>: View {
    private let action: () async throws -> Void
    private let label: () -> Label

    @State private var isLoading = false
    @State private var error: Error?

    public init(
        action: @escaping () async throws -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button {
            guard !isLoading else { return }
            Task {
                isLoading = true
                defer { isLoading = false }
                do {
                    try await action()
                } catch {
                    self.error = error
                }
            }
        } label: {
            if isLoading {
                ProgressView()
            } else {
                label()
            }
        }
        .disabled(isLoading)
    }
}

extension AsyncButton where Label == Text {
    public init(_ title: String, action: @escaping () async throws -> Void) {
        self.init(action: action) { Text(title) }
    }
}
