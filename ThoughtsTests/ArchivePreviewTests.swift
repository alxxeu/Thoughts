import Foundation
import Testing
@testable import Thoughts

struct ArchivePreviewTests {
    @Test func headingAndBulletsShowSeveralLines() {
        #expect(ArchivePreview.text("# Plan\n- one\n- two\n- [x] done") == "Plan\n\u{2022} one\n\u{2022} two\n\u{2611} done")
    }

    @Test func dividerAndCodeFencesAreSkipped() {
        #expect(ArchivePreview.text("--\n```\nlet x = 1\n```\n> quote") == "let x = 1\nquote")
    }

    @Test func emptyCard() {
        #expect(ArchivePreview.text("") == "Empty card")
        #expect(ArchivePreview.text("---\n\n") == "Empty card")
    }

    @Test func inlineMarkersRemoved() {
        #expect(ArchivePreview.text("**Bold** and `code`") == "Bold and code")
    }

    @Test func limitedToFourLines() {
        #expect(ArchivePreview.text("a\nb\nc\nd\ne").components(separatedBy: "\n").count == 4)
    }
}
