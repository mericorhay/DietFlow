import Foundation
import Testing
@testable import Domain

@Suite("Assistant disclosure migration")
struct AssistantConsentTests {
    @Test func planOnlyPermissionMustBeAskedAgain() throws {
        let old = Data(#"{"allowsAssistantSharing":true,"remindersEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        #expect(!settings.allowsAssistantSharing)
        #expect(settings.remindersEnabled)
    }

    @Test func currentPermissionSurvivesRelaunch() throws {
        let settings = AppSettings(allowsAssistantSharing: true)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.allowsAssistantSharing)
    }

    @Test func revokedPermissionStaysRevoked() throws {
        var settings = AppSettings(allowsAssistantSharing: true)
        settings.allowsAssistantSharing = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.allowsAssistantSharing)
    }
}
