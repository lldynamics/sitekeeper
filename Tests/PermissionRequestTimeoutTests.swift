import Foundation
import Testing
@testable import sitekeeper

struct PermissionRequestTimeoutTests {
    @Test func callbackAndTimeoutResumeOnlyOnce() async {
        let result = await PermissionRequestTimeoutSupport.resolve(
            timeout: .seconds(1), fallback: -1
        ) { resume in
            DispatchQueue.concurrentPerform(iterations: 20) { index in
                resume(index)
            }
        }
        #expect((0..<20).contains(result))
    }

    @Test func lateCallbackDoesNotReplaceTimeout() async {
        var reply: (@Sendable (Bool) -> Void)?
        let result = await PermissionRequestTimeoutSupport.resolve(
            timeout: .milliseconds(1), fallback: false
        ) { resume in
            reply = resume
        }
        #expect(!result)
        reply?(true)
        reply?(false)
        await Task.yield()
    }
}
