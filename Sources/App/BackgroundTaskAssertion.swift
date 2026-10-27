import UIKit

/// Keeps the process running while the final save finishes after the app leaves the foreground.
/// The system may expire the assertion early; it is then released without being ended twice.
@MainActor
struct BackgroundTaskAssertion {
    var begin: @MainActor (String, @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    var end: @MainActor (UIBackgroundTaskIdentifier) -> Void

    static let application = BackgroundTaskAssertion(
        begin: { UIApplication.shared.beginBackgroundTask(withName: $0, expirationHandler: $1) },
        end: { UIApplication.shared.endBackgroundTask($0) }
    )

    func run(named name: String, _ work: () async -> Void) async {
        let token = Token(end: end)
        token.identifier = begin(name) { token.finish() }
        await work()
        token.finish()
    }

    @MainActor
    private final class Token {
        var identifier = UIBackgroundTaskIdentifier.invalid
        private let end: @MainActor (UIBackgroundTaskIdentifier) -> Void

        init(end: @escaping @MainActor (UIBackgroundTaskIdentifier) -> Void) {
            self.end = end
        }

        func finish() {
            guard identifier != .invalid else { return }
            end(identifier)
            identifier = .invalid
        }
    }
}
