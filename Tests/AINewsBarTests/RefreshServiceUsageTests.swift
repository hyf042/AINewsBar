import XCTest
import SwiftData
@testable import AINewsBar

@MainActor
final class RefreshServiceUsageTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var rss: MockRSS!
    private var ai: MockAI!
    private var prefs: InMemoryPrefs!
    private var usage: InMemoryUsageRecorder!
    private var service: RefreshService!

    override func setUp() async throws {
        try await super.setUp()
        (container, context) = try TestContainer.make()
        rss = MockRSS()
        ai = MockAI()
        prefs = InMemoryPrefs()
        usage = InMemoryUsageRecorder()
        service = RefreshService(rss: rss, ai: ai, prefs: prefs)
        service.configure(with: context, usage: usage)
    }

    override func tearDown() async throws {
        // 显式 stop() 清理 Timer + inflight task，避免测试间 RunLoop 上孤儿 timer 堆积
        service?.stop()
        service = nil
        usage = nil
        prefs = nil
        ai = nil
        rss = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    private func makeRaw(_ url: String) -> RawArticle {
        RawArticle(title: "T-\(url)", url: url, content: "c", publishedAt: Date())
    }

    private func seedFeed(_ url: String) -> Feed {
        let f = Feed(title: "F", url: url, isEnabled: true)
        context.insert(f)
        try? context.save()
        return f
    }

    // MARK: - 成功路径

    func testRefreshRecordsSummaryUsageForEachSuccess() async {
        ai.summaryUsage = UsageInfo(inputTokens: 100, outputTokens: 50)
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [
            makeRaw("https://a/1"),
            makeRaw("https://a/2"),
            makeRaw("https://a/3")
        ])

        await service.refresh()

        let summaryEntries = usage.entries.filter { $0.scene == .summary }
        XCTAssertEqual(summaryEntries.count, 3)
        XCTAssertTrue(summaryEntries.allSatisfy { $0.success && $0.input == 100 && $0.output == 50 })
        XCTAssertTrue(summaryEntries.allSatisfy { $0.model == "mock-model" })
    }

    func testRefreshRecordsRecommendAndDigestUsage() async {
        ai.summaryUsage = UsageInfo(inputTokens: 10, outputTokens: 20)
        ai.recommendUsage = UsageInfo(inputTokens: 200, outputTokens: 5)
        ai.digestUsage = UsageInfo(inputTokens: 300, outputTokens: 100)

        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [
            makeRaw("https://a/1"),
            makeRaw("https://a/2"),
            makeRaw("https://a/3"),
            makeRaw("https://a/4")
        ])

        await service.refresh()

        let rec = usage.entries.filter { $0.scene == .recommend }
        XCTAssertEqual(rec.count, 1)
        XCTAssertEqual(rec.first?.input, 200)
        XCTAssertEqual(rec.first?.output, 5)
        XCTAssertEqual(rec.first?.success, true)

        let dig = usage.entries.filter { $0.scene == .digest }
        XCTAssertEqual(dig.count, 1)
        XCTAssertEqual(dig.first?.input, 300)
        XCTAssertEqual(dig.first?.output, 100)
        XCTAssertEqual(dig.first?.success, true)
    }

    // MARK: - 失败路径

    func testRefreshRecordsSummaryFailureWithZeroTokens() async {
        struct StubErr: Error {}
        ai.summaryError = StubErr()

        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/1"), makeRaw("https://a/2")])

        await service.refresh()

        let entries = usage.entries.filter { $0.scene == .summary }
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { !$0.success && $0.input == 0 && $0.output == 0 })
    }

    // P10: 摘要大面积失败应触发 AI 不可用 Banner
    func testRefreshMarksAIUnavailableWhenSummaryCoverageLow() async {
        struct StubErr: Error {}
        ai.summaryError = StubErr()
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [
            makeRaw("https://a/1"), makeRaw("https://a/2"), makeRaw("https://a/3"),
            makeRaw("https://a/4"), makeRaw("https://a/5")
        ])

        await service.refresh()

        if case .unavailable = service.aiAvailability {
            // pass
        } else {
            XCTFail("expected .unavailable, got \(service.aiAvailability)")
        }
    }

    func testRefreshRecordsRecommendFailure() async {
        struct StubErr: Error {}
        ai.recommendError = StubErr()
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [
            makeRaw("https://a/1"),
            makeRaw("https://a/2"),
            makeRaw("https://a/3")
        ])

        await service.refresh()

        let rec = usage.entries.filter { $0.scene == .recommend }
        XCTAssertEqual(rec.count, 1)
        XCTAssertEqual(rec.first?.success, false)
        XCTAssertEqual(rec.first?.input, 0)
    }

    func testRefreshRecordsDigestFailure() async {
        struct StubErr: Error {}
        ai.digestError = StubErr()
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [
            makeRaw("https://a/1"),
            makeRaw("https://a/2"),
            makeRaw("https://a/3")
        ])

        await service.refresh()

        let dig = usage.entries.filter { $0.scene == .digest }
        XCTAssertEqual(dig.count, 1)
        XCTAssertEqual(dig.first?.success, false)
    }

    // MARK: - 清理

    func testRefreshTriggersCleanup() async {
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/1")])
        await service.refresh()
        XCTAssertEqual(usage.cleanupCalls, [30])
    }

    func testRefreshWithoutUsageRecorderNoCrash() async {
        let bare = RefreshService(rss: rss, ai: ai, prefs: prefs)
        bare.configure(with: context, usage: nil)
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/1")])
        await bare.refresh()
        // 通过即可：未注入 recorder 应静默跳过 record/cleanup
    }
}
