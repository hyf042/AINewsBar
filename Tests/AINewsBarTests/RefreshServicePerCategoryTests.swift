import XCTest
import SwiftData
@testable import AINewsBar

/// v2-multi-category: 验证 per-cat 状态隔离 + .ai shortcut + force/timer cat 化。
@MainActor
final class RefreshServicePerCategoryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var rss: MockRSS!
    private var ai: MockAI!
    private var prefs: InMemoryPrefs!
    private var service: RefreshService!

    override func setUp() async throws {
        try await super.setUp()
        (container, context) = try TestContainer.make()
        rss = MockRSS()
        ai = MockAI()
        prefs = InMemoryPrefs()
        service = RefreshService(rss: rss, ai: ai, prefs: prefs)
        service.configure(with: context)
    }

    override func tearDown() async throws {
        service?.stop()
        service = nil
        prefs = nil
        ai = nil
        rss = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - 辅助

    private func seedFeed(_ url: String, title: String = "F",
                          category: AINewsBar.Category = .ai) -> Feed {
        let feed = Feed(title: title, url: url, isEnabled: true, category: category)
        context.insert(feed)
        try? context.save()
        return feed
    }

    private func makeRaw(_ url: String, title: String = "T", at: Date = Date()) -> RawArticle {
        RawArticle(title: title, url: url, content: "content-\(title)", publishedAt: at)
    }

    // MARK: - per-cat 状态隔离

    func testStateForReturnsIndependentDefaultsPerCat() {
        let aiState = service.state(for: .ai)
        let earningsState = service.state(for: .earnings)
        let newsState = service.state(for: .news)

        XCTAssertNil(aiState.dailyDigest)
        XCTAssertNil(earningsState.dailyDigest)
        XCTAssertNil(newsState.dailyDigest)

        XCTAssertEqual(aiState.aiAvailability, .unknown)
        XCTAssertEqual(earningsState.aiAvailability, .unknown)
        XCTAssertEqual(newsState.aiAvailability, .unknown)
    }

    func testBackwardCompatPropertiesMirrorAICatState() {
        // service.dailyDigest 等于 state(for: .ai).dailyDigest
        XCTAssertNil(service.dailyDigest)
        XCTAssertNil(service.state(for: .ai).dailyDigest)

        // Setter 写入 .ai cat
        service.dailyDigest = "test-ai"
        XCTAssertEqual(service.state(for: .ai).dailyDigest, "test-ai")

        // 不影响 .earnings / .news
        XCTAssertNil(service.state(for: .earnings).dailyDigest)
        XCTAssertNil(service.state(for: .news).dailyDigest)
    }

    func testBackwardCompatAIAvailabilityMirrorAI() {
        service.aiAvailability = .available
        XCTAssertEqual(service.state(for: .ai).aiAvailability, .available)
        XCTAssertEqual(service.state(for: .earnings).aiAvailability, .unknown,
                       "改 .ai 不应动 .earnings")
    }

    // MARK: - refresh per-cat 隔离

    func testRefreshAICatDoesNotAffectEarningsState() async {
        prefs.apiKey = "test-key"
        let aiFeed = seedFeed("https://ai.com/feed", title: "AI Feed", category: .ai)
        let earningsFeed = seedFeed("https://earn.com/feed", title: "Earn Feed", category: .earnings)
        rss.setSuccess(aiFeed.url, [makeRaw("https://a/1")])
        rss.setSuccess(earningsFeed.url, [makeRaw("https://e/1")])

        // 仅 refresh .ai
        await service.refresh(.ai)

        // .ai state 已更新
        XCTAssertNotNil(service.state(for: .ai).lastRefreshDate)

        // .earnings state 未动
        XCTAssertNil(service.state(for: .earnings).lastRefreshDate)
        XCTAssertNil(service.state(for: .news).lastRefreshDate)

        // SwiftData 中 .ai cat 文章已入库；.earnings 未抓
        let allArticles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        let aiArticles = allArticles.filter { $0.category == AINewsBar.Category.ai.rawValue }
        let earningsArticles = allArticles.filter { $0.category == AINewsBar.Category.earnings.rawValue }
        XCTAssertEqual(aiArticles.count, 1)
        XCTAssertEqual(earningsArticles.count, 0, "仅 refresh AI 不应抓 earnings")
    }

    func testGlobalSummarizingFlagStaysTrueUntilAllConcurrentCatsFinish() async {
        prefs.apiKey = "test-key"
        let aiFeed = seedFeed("https://ai.com/feed", title: "AI Feed", category: .ai)
        let newsFeed = seedFeed("https://news.com/feed", title: "News Feed", category: .news)
        rss.setSuccess(aiFeed.url, [makeRaw("https://a/1", title: "AI")])
        rss.setSuccess(newsFeed.url, [makeRaw("https://n/1", title: "News")])
        ai.summaryDelayByCategoryNanos = [
            .ai: 40_000_000,
            .news: 180_000_000,
        ]

        async let aiRefresh: Void = service.refresh(.ai)
        async let newsRefresh: Void = service.refresh(.news)

        try? await _Concurrency.Task.sleep(nanoseconds: 90_000_000)
        XCTAssertTrue(service.isSummarizing,
                      "AI cat 结束但 news cat 仍在摘要时，全局 summarizing flag 不能提前变 false")
        XCTAssertFalse(service.isSummarizing(category: .ai),
                       "AI cat 摘要结束后，不应继续禁用 AI tab 操作")
        XCTAssertTrue(service.isSummarizing(category: .news),
                      "News cat 仍在摘要时，只应标记 news tab 生成中")

        _ = await (aiRefresh, newsRefresh)
        XCTAssertFalse(service.isSummarizing)
        XCTAssertFalse(service.isSummarizing(category: .ai))
        XCTAssertFalse(service.isSummarizing(category: .news))
    }

    func testSystemWakeRefreshesAllEnabledCats() async {
        prefs.apiKey = "test-key"
        let aiFeed = seedFeed("https://ai.com/feed", title: "AI Feed", category: .ai)
        let earningsFeed = seedFeed("https://earn.com/feed", title: "Earn Feed", category: .earnings)
        let newsFeed = seedFeed("https://news.com/feed", title: "News Feed", category: .news)
        rss.setSuccess(aiFeed.url, [makeRaw("https://a/1", title: "AI")])
        rss.setSuccess(earningsFeed.url, [makeRaw("https://e/1", title: "Earnings")])
        rss.setSuccess(newsFeed.url, [makeRaw("https://n/1", title: "News")])

        await service.handleSystemWake()

        XCTAssertNotNil(service.state(for: .ai).lastRefreshDate)
        XCTAssertNotNil(service.state(for: .earnings).lastRefreshDate)
        XCTAssertNotNil(service.state(for: .news).lastRefreshDate)
        XCTAssertEqual(rss.fetchCount, 3)
    }

    // MARK: - force regenerate per-cat 隔离

    func testForceRegenerateRecommendOnlyForRequestedCat() async {
        prefs.apiKey = "test-key"
        // 给 .ai 5 篇带摘要的文章作为推荐候选
        for i in 0..<5 {
            let article = Article(
                title: "T\(i)", url: "https://a/\(i)",
                publishedAt: Date(), feedID: UUID(), feedTitle: "F",
                category: .ai, accepted: true
            )
            article.aiSummary = "s\(i)"
            context.insert(article)
        }
        try? context.save()

        // recommendProvider 返回前 5 个 id
        ai.recommendProvider = { items in Array(items.prefix(5).map(\.id)) }

        await service.forceRegenerateRecommend(.ai)

        XCTAssertFalse(service.state(for: .ai).recommendedArticleIDs.isEmpty,
                       ".ai 推荐应已生成")
        XCTAssertTrue(service.state(for: .earnings).recommendedArticleIDs.isEmpty,
                      ".earnings 不应被触动")
        XCTAssertEqual(ai.capturedRecommendCats, [.ai],
                       "AI mock 应只收到 .ai cat 调用")
    }

    // MARK: - 跨日重置全 cat 遍历

    func testCrossDayResetClearsAllCats() {
        // 先 set 三 cat 的状态
        for cat in AINewsBar.Category.allCases {
            service.states[cat]?.dailyDigest = "digest-\(cat.rawValue)"
        }
        XCTAssertNotNil(service.state(for: .ai).dailyDigest)
        XCTAssertNotNil(service.state(for: .earnings).dailyDigest)
        XCTAssertNotNil(service.state(for: .news).dailyDigest)

        // 模拟跨日：lastResetCheckDate 设为昨天
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        service.lastResetCheckDate = yesterday

        service.resetCrossedDayStateIfNeeded()

        XCTAssertNil(service.state(for: .ai).dailyDigest, "跨日应清 .ai")
        XCTAssertNil(service.state(for: .earnings).dailyDigest, "跨日应清 .earnings")
        XCTAssertNil(service.state(for: .news).dailyDigest, "跨日应清 .news")
    }

    // MARK: - per-cat aiAvailability 设置不影响其他 cat

    func testAIErrorInOneCatDoesNotPollutionOthers() async {
        prefs.apiKey = "test-key"
        // 给 .ai 5 篇候选，但 recommend 报错
        for i in 0..<5 {
            let article = Article(
                title: "T\(i)", url: "https://a/\(i)",
                publishedAt: Date(), feedID: UUID(), feedTitle: "F",
                category: .ai, accepted: true
            )
            article.aiSummary = "s\(i)"
            context.insert(article)
        }
        try? context.save()

        struct E: Error { let msg = "fail" }
        ai.recommendError = E()

        await service.forceRegenerateRecommend(.ai)

        // .ai 应设为 .unavailable
        switch service.state(for: .ai).aiAvailability {
        case .unavailable: break  // 期望
        default: XCTFail(".ai 应进入 unavailable 状态")
        }

        // .earnings / .news 不受影响
        XCTAssertEqual(service.state(for: .earnings).aiAvailability, .unknown)
        XCTAssertEqual(service.state(for: .news).aiAvailability, .unknown)
    }

    // MARK: - states 字典完整性（防御性）

    func testStatesDictionaryContainsAllCategories() {
        XCTAssertEqual(service.states.count, 3)
        XCTAssertNotNil(service.states[.ai])
        XCTAssertNotNil(service.states[.earnings])
        XCTAssertNotNil(service.states[.news])
    }
}
