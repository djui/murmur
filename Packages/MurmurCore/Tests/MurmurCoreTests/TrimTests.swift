import Foundation
import Testing
@testable import MurmurCore

@Suite struct TrimTests {
    func project() -> Project {
        var p = Project()
        p.duration = 100
        p.words = [Word(text: "before", start: 2, end: 3), Word(text: "kept", start: 20, end: 21),
                   Word(text: "edge", start: 9.6, end: 10.6), Word(text: "after", start: 95, end: 96)]
        p.marks = [Mark(name: "early", start: 1, end: 5), Mark(name: "across", start: 5, end: 15),
                   Mark(name: "inside", start: 30, end: 40)]
        return p
    }

    @Test func trimsWordsAndMarksAndKeepsTheRest() throws {
        var p = project()
        p.trim(to: 10...90)
        #expect(p.span == 10...90)
        #expect(p.words.map(\.text) == ["kept", "edge"])   // edge: its middle (10.1) is inside
        #expect(p.marks.map(\.name) == ["across", "inside"])
        #expect(p.marks.first?.start == 10)
        let trim = try #require(p.trim)
        #expect(trim.words.map(\.text) == ["before", "after"])
        #expect(trim.marks.map(\.name) == ["early"])
    }

    @Test func removingTheTrimPutsEverythingBackInOrder() {
        var p = project()
        p.trim(to: 10...90)
        p.removeTrim()
        #expect(p.trim == nil)
        #expect(p.span == 0...100)
        #expect(p.words.map(\.text) == ["before", "edge", "kept", "after"])
        #expect(Set(p.marks.map(\.name)) == ["early", "across", "inside"])
    }

    @Test func trimmingAgainStartsFromTheWholeFile() {
        var p = project()
        p.trim(to: 50...90)
        p.trim(to: 0...30)
        #expect(Set(p.words.map(\.text)) == ["before", "kept", "edge"])
        #expect(p.trim?.words.map(\.text) == ["after"])
        #expect(p.span == 0...30)
    }

    @Test func rangeIsClampedToTheFile() {
        var p = project()
        p.trim(to: -5...500)
        #expect(p.span == 0...100)
    }

    @Test func trimRoundTripsThroughJSON() throws {
        var p = project()
        p.trim(to: 10...90)
        let enc = JSONEncoder(), dec = JSONDecoder()
        enc.dateEncodingStrategy = .iso8601; dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(Project.self, from: enc.encode(p))
        #expect(back.trim == p.trim)
    }
}
