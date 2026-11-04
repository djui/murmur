import Foundation
import Testing
@testable import MurmurCore

@Suite struct TagTests {
    @Test func normalizesSpacingCaseAndOrder() {
        #expect(Tags.normalize(["  meetings ", "1:1", "Meetings", "", "user   interviews", "Interviews"])
                == ["1:1", "Interviews", "meetings", "user interviews"])
        #expect(Tags.clean("   ") == nil)
    }

    @Test func addRemoveAndRename() {
        var p = Project()
        #expect(p.tagList.isEmpty)
        p.addTag("Interviews")
        p.addTag("interviews")
        p.addTag("1:1")
        #expect(p.tagList == ["1:1", "Interviews"])
        #expect(p.hasTag("INTERVIEWS"))
        p.renameTag("1:1", to: "Interviews")
        #expect(p.tagList == ["Interviews"])
        p.renameTag("interviews", to: "Research")
        #expect(p.tagList == ["Research"])
        p.removeTag("research")
        #expect(p.tags == nil)
    }

    @Test func olderFilesWithoutTagsStillOpenAndRoundTrip() throws {
        var p = Project()
        let untagged = try p.encoded()
        #expect(!String(decoding: untagged, as: UTF8.self).contains("\"tags\""))
        #expect(try Project.decode(untagged).tags == nil)
        p.setTags(["Meetings", "1:1"])
        #expect(try Project.decode(p.encoded()).tagList == ["1:1", "Meetings"])
    }
}
