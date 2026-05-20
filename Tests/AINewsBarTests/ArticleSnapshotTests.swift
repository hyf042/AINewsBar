import XCTest
@testable import AINewsBar

final class ArticleSnapshotTests: XCTestCase {

    private func snap(_ items: [(title: String, summary: String?)]) -> ArticleSnapshot {
        ArticleSnapshot(all: items.map {
            ArticleSnapshot.Item(id: UUID(), title: $0.title, summary: $0.summary)
        })
    }

    func testEmptySnapshot() {
        let s = ArticleSnapshot(all: [])
        XCTAssertEqual(s.summarizedCount, 0)
        XCTAssertTrue(s.summarized.isEmpty)
        XCTAssertTrue(s.all.isEmpty)
    }

    func testSummarizedFiltering() {
        let s = snap([
            ("A", "sa"),
            ("B", nil),
            ("C", "sc")
        ])
        XCTAssertEqual(s.summarizedCount, 2)
        XCTAssertEqual(s.summarized.map(\.title), ["A", "C"])
    }

    func testAllKeepsEverything() {
        let s = snap([("A", "sa"), ("B", nil), ("C", "sc")])
        XCTAssertEqual(s.all.count, 3, "all 含全部文章（含无摘要）")
        XCTAssertNil(s.all[1].summary)
    }
}
