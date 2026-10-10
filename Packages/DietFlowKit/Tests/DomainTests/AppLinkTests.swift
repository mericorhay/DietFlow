import Foundation
import Testing
import Domain

struct AppLinkTests {
    @Test func everyLinkReadsBackAsItself() throws {
        let key = OccurrenceKey(mealID: UUID(), day: day(2026, 10, 5))
        for link in [AppLink.today, .meal(key), .cook(key), .plan, .widgets, .importPlan] {
            #expect(AppLink(url: link.url) == link)
        }
    }

    @Test func aMealLinkNamesTheMealAndTheDay() throws {
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let link = AppLink.meal(OccurrenceKey(mealID: id, day: day(2026, 10, 5)))
        #expect(link.url.absoluteString == "dietflow://meal/6F9619FF-8B86-D011-B42D-00C04FC964FF@2026-10-05")
    }

    @Test func otherLinksAreIgnored() throws {
        #expect(AppLink(url: try #require(URL(string: "https://example.com/meal/x"))) == nil)
        #expect(AppLink(url: try #require(URL(string: "dietflow://meal/not-a-key"))) == nil)
        #expect(AppLink(url: try #require(URL(string: "dietflow://elsewhere"))) == nil)
        #expect(AppLink(url: try #require(URL(string: "DIETFLOW://today"))) == .today)
    }
}
