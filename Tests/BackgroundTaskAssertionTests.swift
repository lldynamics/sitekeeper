import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct BackgroundTaskAssertionTests {
    @Test func endsTheAssertionOnceAfterTheSaveFinishes() async {
        var events: [String] = []
        let assertion = BackgroundTaskAssertion(
            begin: { name, _ in
                events.append("begin \(name)")
                return UIBackgroundTaskIdentifier(rawValue: 7)
            },
            end: { events.append("end \($0.rawValue)") }
        )
        await assertion.run(named: "save") { events.append("work") }
        #expect(events == ["begin save", "work", "end 7"])
    }

    @Test func expirationReleasesTheAssertionWithoutEndingItTwice() async {
        var ended: [Int] = []
        var expire: (@MainActor @Sendable () -> Void)?
        let assertion = BackgroundTaskAssertion(
            begin: { _, handler in
                expire = handler
                return UIBackgroundTaskIdentifier(rawValue: 9)
            },
            end: { ended.append($0.rawValue) }
        )
        var workFinished = false
        await assertion.run(named: "save") {
            expire?()
            workFinished = true
        }
        #expect(workFinished)
        #expect(ended == [9])
    }

    @Test func refusedAssertionStillRunsTheSave() async {
        var ended = 0
        let assertion = BackgroundTaskAssertion(begin: { _, _ in .invalid }, end: { _ in ended += 1 })
        var workFinished = false
        await assertion.run(named: "save") { workFinished = true }
        #expect(workFinished)
        #expect(ended == 0)
    }
}
