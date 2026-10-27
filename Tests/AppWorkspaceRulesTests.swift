import Testing
import CoreGraphics
@testable import sitekeeper

struct AppWorkspaceRulesTests {
    @Test func columnsRequireBothReadablePanesAndKeyboardRoom() {
        #expect(!AppWorkspaceRules.permitsColumns(width: 466, height: 678, primary: 340, secondary: 300))
        #expect(AppWorkspaceRules.permitsColumns(width: 900, height: 590, primary: 340, secondary: 300))
        #expect(!AppWorkspaceRules.permitsColumns(width: 900, height: 200, primary: 340, secondary: 300))
        #expect(!AppWorkspaceRules.permitsColumns(width: 900, height: 590, primary: 520, secondary: 470))
        #expect(!AppWorkspaceRules.permitsColumns(width: .infinity, height: 590, primary: 340, secondary: 300))
    }
}
