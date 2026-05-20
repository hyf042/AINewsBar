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
        XCTAssertTrue(s.summarizedPairs.isEmpty)
        XCTAssertTrue(s.pickInputs.isEmpty)
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

    func testSummarizedPairsMapping() {
        let s = snap([
            ("A", "sa"),
            ("B", nil),
            ("C", "sc")
        ])
        let pairs = s.summarizedPairs
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].title, "A")
        XCTAssertEqual(pairs[0].summary, "sa")
        XCTAssertEqual(pairs[1].title, "C")
    }

    func testPickInputsKeepsAll() {
        let s = snap([("A", "sa"), ("B", nil), ("C", "sc")])
        let picks = s.pickInputs
        XCTAssertEqual(picks.count, 3, "pickInputs 含全部文章（含无摘要）")
        XCTAssertNil(picks[1].summary)
    }
}
