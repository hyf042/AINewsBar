import XCTest
import SwiftData
@testable import AINewsBar

/// v2-multi-category: 验证 per-cat 状态隔离 + force/timer cat 化。
/// （shortcut backward compat 测试已删 —— H1 review 后 .ai shortcut properties 已移除）
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

    // MARK: - markAvailability 公开 setter

    func testMarkAvailabilitySetsOnlyTargetCat() {
        service.markAvailability(.available, for: .ai)
        XCTAssertEqual(service.state(for: .ai).aiAvailability, .available)
        XCTAssertEqual(service.state(for: .earnings).aiAvailability, .unknown,
                       "markAvailability 应只动目标 cat")
        XCTAssertEqual(service.state(for: .news).aiAvailability, .unknown)
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
        // 先 set 三 cat 的状态（_testMutate 走 mutate 路径触发 @Published 通知）
        for cat in AINewsBar.Category.allCases {
            service._testMutate(for: cat) { $0.dailyDigest = "digest-\(cat.rawValue)" }
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

    // MARK: - hasNewArticles 语义：可见新文章 vs RSS 入库数

    /// 财报 cat 本轮新抓文章全部被 filter reject 时，没有任何用户可见的新内容，
    /// 不应触发 recommend/digest 重生（旧实现用 RSS 入库数当 hasNewArticles，会白烧 token）。
    private func seedVisibleEarningsHistory(count: Int = 5) {
        for i in 0..<count {
            let a = Article(
                title: "Old\(i)", url: "https://e/old\(i)",
                publishedAt: Date(), feedID: UUID(), feedTitle: "F",
                category: .earnings, accepted: true
            )
            a.aiSummary = "s\(i)"
            context.insert(a)
        }
        try? context.save()
        // 预置已有推荐 + 已有日报（4 小时前，digest 时间窗已过），count 对齐历史数：
        // 这样只剩 hasNewArticles 一条能触发重生，精准暴露语义错误。
        service._testMutate(for: .earnings) {
            $0.recommendedArticleIDs = [UUID()]   // isEmpty=false
            $0.recommendArticleCount = count
            $0.dailyDigest = "old digest"
            $0.lastDigestDate = Date().addingTimeInterval(-4 * 3600)
            $0.digestArticleCount = count
        }
    }

    func testEarningsAllFilterRejectedDoesNotRegenerateDerivedContent() async {
        prefs.apiKey = "test-key"
        seedVisibleEarningsHistory()

        let feed = seedFeed("https://earn.com/feed", title: "Earn", category: .earnings)
        rss.setSuccess(feed.url, [
            makeRaw("https://e/new1", title: "New1"),
            makeRaw("https://e/new2", title: "New2"),
        ])
        ai.classifyProvider = { _, _ in false }   // 全 reject

        let recBefore = ai.recommendCallCount
        let digBefore = ai.digestCallCount

        await service.refresh(.earnings)

        XCTAssertEqual(ai.classifyCallCount, 2, "2 篇新文章应都过 filter")
        XCTAssertEqual(ai.recommendCallCount, recBefore,
                       "全 reject 无可见新内容，不应重新生成推荐")
        XCTAssertEqual(ai.digestCallCount, digBefore,
                       "全 reject 无可见新内容，不应重新生成日报")
    }

    /// 反向保护：filter 部分 accept 时（有可见新内容）仍应重生，避免修复过度把正常 case 挡掉。
    func testEarningsSomeFilterAcceptedRegeneratesRecommend() async {
        prefs.apiKey = "test-key"
        seedVisibleEarningsHistory()

        let feed = seedFeed("https://earn.com/feed", title: "Earn", category: .earnings)
        rss.setSuccess(feed.url, [
            makeRaw("https://e/new1", title: "Accept"),
            makeRaw("https://e/new2", title: "Reject"),
        ])
        ai.classifyProvider = { title, _ in title == "Accept" }   // 仅 1 篇通过

        let recBefore = ai.recommendCallCount

        await service.refresh(.earnings)

        XCTAssertGreaterThan(ai.recommendCallCount, recBefore,
                             "有新文章通过 filter（可见新内容），应重新生成推荐")
    }
}
