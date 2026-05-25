import XCTest
import SwiftData
@testable import AINewsBar

@MainActor
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

    // 第八轮 P2 review：captureOrThrow 必须按 publishedAt 倒序，
    // 否则 prompt prefix(50) / prefix(20) 截断时随机切掉最新文章。
    // sort 在内存中执行（避开 SwiftData SortDescriptor in-memory 触发的 SIGTRAP）
    //
    // 注：必须 named binding 保留 container —— 用 `(_, context)` 会让 container
    // 立即被 ARC 释放，mainContext 失效后 insert/save 触发 SIGTRAP
    func testCaptureOrThrowSortsByPublishedAtDescending() throws {
        let (container, context) = try TestContainer.make()
        _ = container  // 显式保留，避免 ARC 提前释放
        let now = Date()
        // 故意按非时间顺序 insert（older → newest → middle），验证不依赖插入顺序
        let older = Article(
            title: "old", url: "https://a/old",
            publishedAt: now.addingTimeInterval(-3600),
            feedID: UUID(), feedTitle: "F",
            category: .ai, accepted: true
        )
        let newest = Article(
            title: "new", url: "https://a/new",
            publishedAt: now,
            feedID: UUID(), feedTitle: "F",
            category: .ai, accepted: true
        )
        let middle = Article(
            title: "mid", url: "https://a/mid",
            publishedAt: now.addingTimeInterval(-1800),
            feedID: UUID(), feedTitle: "F",
            category: .ai, accepted: true
        )
        context.insert(older)
        context.insert(newest)
        context.insert(middle)
        try context.save()

        let snapshot = try ArticleSnapshot.captureOrThrow(from: context, category: .ai)

        XCTAssertEqual(snapshot.all.map(\.title), ["new", "mid", "old"],
                       "snapshot.all 必须按 publishedAt 倒序，prompt prefix(N) 才能切到最新文章")
    }
}
