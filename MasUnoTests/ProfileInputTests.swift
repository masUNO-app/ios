import Foundation
import Testing
@testable import masUNO

@MainActor
struct ProfileInputTests {
    @Test func classYearsRunFromThisYearThroughSixYearsOut() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let midYear = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12)))
        #expect(ProfileInput.classYears(now: midYear) == [2026, 2027, 2028, 2029, 2030, 2031, 2032])
        let newYearsEve = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23)))
        #expect(ProfileInput.classYears(now: newYearsEve).first == 2026)
    }

    @Test func nameProblemCatchesBlankAndUnfriendlyNames() {
        #expect(ProfileInput.nameProblem("") == .missing)
        #expect(ProfileInput.nameProblem("   ") == .missing)
        #expect(ProfileInput.nameProblem("Puto") == .unfriendly)
        #expect(ProfileInput.nameProblem("Emilio") == nil)
        #expect(ProfileInput.nameProblem(" José María ") == nil)
    }

    @Test func previewNameShowsFirstNameAndLastInitial() {
        #expect(ProfileInput.previewName(first: " Emilio ", last: "garza") == "Emilio G.")
        #expect(ProfileInput.previewName(first: "Emilio", last: "  ") == "Emilio")
        #expect(ProfileInput.previewName(first: "", last: "") == "")
    }

    @Test func setToggleInsertsThenRemoves() {
        var sports: Set<Activity> = []
        let basketball = Activity.builtIn[0]
        sports.toggle(basketball)
        #expect(sports == [basketball])
        sports.toggle(basketball)
        #expect(sports.isEmpty)
    }
}
