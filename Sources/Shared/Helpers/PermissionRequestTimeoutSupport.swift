import Foundation

enum PermissionRequestTimeoutSupport {
    static let defaultTimeout: DispatchTimeInterval = .seconds(8)

    static func resolve<Value>(
        timeout: DispatchTimeInterval = defaultTimeout,
        fallback: Value,
        operation: (@escaping (Value) -> Void) -> Void
    ) async -> Value {
        await withCheckedContinuation { continuation in
            let resumeQueue = DispatchQueue(label: "permission-request-timeout.resume")
            var didResume = false

            let resume: (Value) -> Void = { value in
                resumeQueue.async {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: value)
                }
            }

            operation { value in
                resume(value)
            }

            resumeQueue.asyncAfter(deadline: .now() + timeout) {
                resume(fallback)
            }
        }
    }
}
