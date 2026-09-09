import Foundation

enum PermissionRequestTimeoutSupport {
    static let defaultTimeout: DispatchTimeInterval = .seconds(8)

    static func resolve<Value: Sendable>(
        timeout: DispatchTimeInterval = defaultTimeout,
        fallback: Value,
        isolation: isolated (any Actor)? = #isolation,
        operation: (@escaping @Sendable (Value) -> Void) -> Void
    ) async -> Value {
        await withCheckedContinuation { continuation in
            let resolution = PermissionRequestResolution(continuation: continuation)
            let resume: @Sendable (Value) -> Void = { value in
                Task { await resolution.resume(returning: value) }
            }

            operation { value in
                resume(value)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resume(fallback)
            }
        }
    }
}

private actor PermissionRequestResolution<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?

    init(continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}
