import Foundation
import Testing
import Domain

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    BillingCycle.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

struct BillingCycleTests {
    @Test func aWindowRunsFromTheBillingDayToTheNext() {
        let window = BillingCycle.monthlyWindow(anchoredAt: utc(2026, 10, 16, 9, 30), containing: utc(2026, 10, 20))
        #expect(window.start == utc(2026, 10, 16, 9, 30))
        #expect(window.end == utc(2026, 11, 16, 9, 30))
    }

    @Test func theRenewalMomentBelongsToTheNewWindow() {
        let anchor = utc(2026, 10, 16, 9, 30)
        #expect(BillingCycle.monthlyWindow(anchoredAt: anchor, containing: utc(2026, 11, 16, 9, 29)).start == anchor)
        #expect(BillingCycle.monthlyWindow(anchoredAt: anchor, containing: utc(2026, 11, 16, 9, 30)).start == utc(2026, 11, 16, 9, 30))
    }

    @Test func aBillingDayOnThe31stDoesNotDriftAfterAShortMonth() {
        let anchor = utc(2026, 1, 31, 12)
        let february = BillingCycle.monthlyWindow(anchoredAt: anchor, containing: utc(2026, 2, 10))
        #expect(february.start == anchor)
        #expect(february.end == utc(2026, 2, 28, 12))

        let march = BillingCycle.monthlyWindow(anchoredAt: anchor, containing: utc(2026, 3, 10))
        #expect(march.start == utc(2026, 2, 28, 12))
        // Back on the 31st: measured from the anchor, not from February's 28th.
        #expect(march.end == utc(2026, 3, 31, 12))

        let april = BillingCycle.monthlyWindow(anchoredAt: anchor, containing: utc(2026, 4, 5))
        #expect(april.start == utc(2026, 3, 31, 12))
        #expect(april.end == utc(2026, 4, 30, 12))
    }

    @Test func theLastDayOfFebruaryInALeapYearIsThe29th() {
        let window = BillingCycle.monthlyWindow(anchoredAt: utc(2028, 1, 31), containing: utc(2028, 2, 15))
        #expect(window.end == utc(2028, 2, 29))
    }

    @Test func windowsCarryOnAcrossTheYear() {
        let window = BillingCycle.monthlyWindow(anchoredAt: utc(2026, 10, 16), containing: utc(2027, 1, 2))
        #expect(window.start == utc(2026, 12, 16))
        #expect(window.end == utc(2027, 1, 16))
    }

    @Test func everyDayOfThreeYearsFallsInExactlyOneWindowThatHoldsIt() {
        let anchor = utc(2026, 1, 31, 23, 59)
        var day = anchor
        var previous: BillingWindow?
        for _ in 0..<(3 * 366) {
            let window = BillingCycle.monthlyWindow(anchoredAt: anchor, containing: day)
            #expect(window.contains(day))
            #expect(window.end > window.start)
            if let previous, previous != window {
                // Windows meet end to start, with no gap and no overlap.
                #expect(previous.end == window.start)
            }
            previous = window
            day = day.addingTimeInterval(86_400)
        }
    }

    @Test func aDateBeforeTheAnchorGetsTheFirstWindow() {
        let anchor = utc(2026, 10, 16)
        #expect(BillingCycle.monthlyWindow(anchoredAt: anchor, containing: utc(2026, 9, 1)).start == anchor)
    }

    @Test func aSevenDayTrialEndsAWeekLaterToTheMinute() {
        let end = BillingCycle.date(byAdding: .init(value: 7, unit: .day), to: utc(2026, 10, 6, 21, 15))
        #expect(end == utc(2026, 10, 13, 21, 15))
    }

    @Test func aMonthFromThe31stIsTheLastDayOfAShorterMonth() {
        #expect(BillingCycle.date(byAdding: .init(value: 1, unit: .month), to: utc(2026, 1, 31)) == utc(2026, 2, 28))
        #expect(BillingCycle.date(byAdding: .init(value: 1, unit: .year), to: utc(2028, 2, 29)) == utc(2029, 2, 28))
        #expect(BillingCycle.date(byAdding: .init(value: 2, unit: .week), to: utc(2026, 12, 25)) == utc(2027, 1, 8))
    }

    @Test func periodsAreNamedSoThatANewOneIsANewCount() {
        #expect(BillingCycle.monthKey(for: utc(2026, 10, 31, 23, 59)) == "2026-10")
        #expect(BillingCycle.monthKey(for: utc(2026, 11, 1)) == "2026-11")
        let window = BillingCycle.monthlyWindow(anchoredAt: utc(2026, 10, 16), containing: utc(2026, 11, 20))
        #expect(BillingCycle.windowKey(for: window) == "plus-2026-11-16")
    }
}

struct EntitlementWindowTests {
    @Test func aMonthlySubscriptionCountsOverThePeriodTheStoreCharged() {
        let entitlement = PlusEntitlement(kind: .monthly, periodStart: utc(2026, 10, 16, 8), periodEnd: utc(2026, 11, 16, 8), willRenew: true, isTrial: false)
        let window = entitlement.allowanceWindow(containing: utc(2026, 11, 1))
        #expect(window == BillingWindow(start: utc(2026, 10, 16, 8), end: utc(2026, 11, 16, 8)))
    }

    @Test func theFreeTrialIsItsOwnShortWindow() {
        let entitlement = PlusEntitlement(kind: .monthly, periodStart: utc(2026, 10, 6), periodEnd: utc(2026, 10, 13), willRenew: true, isTrial: true)
        #expect(entitlement.allowanceWindow(containing: utc(2026, 10, 9)).end == utc(2026, 10, 13))
    }

    @Test func aYearIsStillCountedMonthByMonth() {
        let entitlement = PlusEntitlement(kind: .yearly, periodStart: utc(2026, 10, 16), periodEnd: utc(2027, 10, 16), willRenew: true, isTrial: false)
        let window = entitlement.allowanceWindow(containing: utc(2027, 3, 1))
        #expect(window == BillingWindow(start: utc(2027, 2, 16), end: utc(2027, 3, 16)))
    }

    @Test func aLifetimePurchaseGetsAFreshAllowanceEveryMonthFromTheDayItWasBought() {
        let entitlement = PlusEntitlement(kind: .lifetime, periodStart: utc(2026, 10, 16), periodEnd: nil, willRenew: false, isTrial: false)
        let window = entitlement.allowanceWindow(containing: utc(2030, 6, 20))
        #expect(window == BillingWindow(start: utc(2030, 6, 16), end: utc(2030, 7, 16)))
    }

    @Test func aStalePeriodFromTheLastLaunchStillGivesAWindowThatHoldsToday() {
        // The store has not answered yet and the remembered period ended yesterday.
        let entitlement = PlusEntitlement(kind: .monthly, periodStart: utc(2026, 10, 16), periodEnd: utc(2026, 11, 16), willRenew: true, isTrial: false)
        #expect(entitlement.allowanceWindow(containing: utc(2026, 11, 17)).contains(utc(2026, 11, 17)))
    }
}

struct AccessPolicyTests {
    @Test func theFreeTierGetsATasteOfTheAssistant() {
        var ledger = UsageLedger(period: "2026-10")
        #expect(AccessPolicy.decide(.aiPlan, tier: .free, ledger: ledger) == .allowed)
        ledger.record(.aiPlan)
        ledger.record(.aiPlan)
        #expect(AccessPolicy.decide(.aiPlan, tier: .free, ledger: ledger) == .limitReached(limit: 2))
        #expect(AccessPolicy.remaining(.aiPlan, tier: .free, ledger: ledger) == 0)
        // The same count is nowhere near the Plus allowance.
        #expect(AccessPolicy.decide(.aiPlan, tier: .plus, ledger: ledger) == .allowed)
    }

    @Test func aSecondPlanIsPlusOnly() {
        let ledger = UsageLedger(period: "2026-10")
        #expect(AccessPolicy.decide(.additionalPlan, tier: .free, ledger: ledger) == .plusOnly)
        #expect(AccessPolicy.decide(.additionalPlan, tier: .plus, ledger: ledger) == .allowed)
        #expect(AccessPolicy.remaining(.additionalPlan, tier: .plus, ledger: ledger) == nil)
    }

    @Test func aFailedAttemptIsGivenBack() {
        var ledger = UsageLedger(period: "2026-10")
        ledger.record(.aiPlan)
        ledger.refund(.aiPlan)
        ledger.refund(.aiPlan)
        #expect(ledger.used(.aiPlan) == 0)
    }
}
