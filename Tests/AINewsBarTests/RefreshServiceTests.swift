import XCTest
import SwiftData
@testable import AINewsBar

@MainActor
final class RefreshServiceTests: XCTestCase {

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
        // 不调 configure() 以避免启动 timer；测试中直接注入 modelContext 通过 configure
        service.configure(with: context)
    }

    override func tearDown() async throws {
        // 显式 stop() 清理 Timer.scheduledTimer，避免 N 个测试实例在 RunLoop 上堆积孤儿 timer
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

    private func makeRaw(_ url: String, title: String = "T", at: Date = Date()) -> RawArticle {
        RawArticle(title: title, url: url, content: "content-\(title)", publishedAt: at)
    }

    private func makeRawNoDate(_ url: String, title: String = "T") -> RawArticle {
        RawArticle(title: title, url: url, content: "content-\(title)", publishedAt: nil)
    }

    private func seedFeed(_ url: String, title: String = "F") -> Feed {
        let feed = Feed(title: title, url: url, isEnabled: true)
        context.insert(feed)
        try? context.save()
        return feed
    }

    private func fetchArticles() -> [Article] {
        (try? context.fetch(FetchDescriptor<Article>())) ?? []
    }

    // MARK: - refresh 基础

    func testRefreshInsertsNewArticles() async {
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/1"), makeRaw("https://a/2")])

        await service.refresh()

        XCTAssertEqual(fetchArticles().count, 2)
        XCTAssertNotNil(service.lastRefreshDate)
    }

    // P11: 无 pubDate 的 RawArticle 不入库（避免每天重生脏文章）
    func testRefreshSkipsArticlesWithoutPublishedAt() async {
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [
            makeRaw("https://a/with-date"),
            makeRawNoDate("https://a/no-date")
        ])
        await service.refresh()
        let urls = fetchArticles().map(\.url).sorted()
        XCTAssertEqual(urls, ["https://a/with-date"], "无 pubDate 的文章应被丢弃")
    }

    func testRefreshSkipsDuplicateURLs() async {
        let feed = seedFeed("https://f1.com/feed")
        // 已存在的文章
        let existing = Article(title: "old", url: "https://a/1", publishedAt: Date(),
                               feedID: feed.id, feedTitle: feed.title)
        context.insert(existing)
        try? context.save()

        rss.setSuccess(feed.url, [makeRaw("https://a/1"), makeRaw("https://a/2")])
        await service.refresh()

        let urls = fetchArticles().map(\.url).sorted()
        XCTAssertEqual(urls, ["https://a/1", "https://a/2"], "已有 URL 不应重复插入")
    }

    // C2: 跨刷新批次内 URL 去重
    func testRefreshDedupsAcrossFeedsInSameBatch() async {
        let f1 = seedFeed("https://f1.com/feed", title: "F1")
        let f2 = seedFeed("https://f2.com/feed", title: "F2")
        // 两个 feed 都返回同一篇文章
        rss.setSuccess(f1.url, [makeRaw("https://shared/1", title: "Shared")])
        rss.setSuccess(f2.url, [makeRaw("https://shared/1", title: "Shared")])

        await service.refresh()

        let articles = fetchArticles().filter { $0.url == "https://shared/1" }
        XCTAssertEqual(articles.count, 1, "C2: 同批次内同 URL 只插入一次")
    }

    func testRefreshFiltersOldArticles() async {
        let feed = seedFeed("https://f1.com/feed")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let today = Date()

        rss.setSuccess(feed.url, [
            makeRaw("https://a/old", at: yesterday),
            makeRaw("https://a/today", at: today)
        ])

        await service.refresh()
        let urls = fetchArticles().map(\.url)
        XCTAssertTrue(urls.contains("https://a/today"))
        XCTAssertFalse(urls.contains("https://a/old"), "昨天的文章不应入库")
    }

    func testRefreshDisabledFeedNotFetched() async {
        let feed = Feed(title: "F", url: "https://f1.com", isEnabled: false)
        context.insert(feed)
        try? context.save()
        rss.setSuccess(feed.url, [makeRaw("https://a/1")])

        await service.refresh()
        XCTAssertEqual(rss.fetchCount, 0)
        XCTAssertEqual(fetchArticles().count, 0)
    }

    func testRefreshRecordsErrors() async {
        let feed = seedFeed("https://f1.com/feed")
        rss.setFailure(feed.url, URLError(.timedOut))

        await service.refresh()
        XCTAssertEqual(service.lastFetchErrorCount, 1)
        XCTAssertNotNil(service.lastError)
    }

    // MARK: - AI 不可用

    func testRefreshMarksAIUnavailableWhenNoAPIKey() async {
        prefs.apiKey = nil
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/1")])

        await service.refresh()
        if case .unavailable = service.aiAvailability {
            // OK
        } else {
            XCTFail("aiAvailability 应为 unavailable，实际：\(service.aiAvailability)")
        }
        XCTAssertEqual(ai.summaryCallCount, 0, "无 API Key 时不应调 AI")
    }

    // MARK: - 摘要生成

    func testRefreshGeneratesSummariesForPending() async {
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, [
            makeRaw("https://a/1", title: "T1"),
            makeRaw("https://a/2", title: "T2")
        ])
        ai.summaryProvider = { title, _ in "summary-\(title)" }

        await service.refresh()

        let summaries = fetchArticles().compactMap(\.aiSummary).sorted()
        XCTAssertEqual(summaries, ["summary-T1", "summary-T2"])
    }

    func testRefreshSkipsArticlesWithExistingSummary() async {
        let feed = seedFeed("https://f1.com/feed")
        let existing = Article(title: "old", url: "https://a/0", publishedAt: Date(),
                               feedID: feed.id, feedTitle: feed.title)
        existing.aiSummary = "已有摘要"
        context.insert(existing)
        try? context.save()

        rss.setSuccess(feed.url, [makeRaw("https://a/1", title: "T1")])
        await service.refresh()

        XCTAssertEqual(ai.summaryCallCount, 1, "只为新文章生成摘要")
        XCTAssertEqual(existing.aiSummary, "已有摘要", "已有摘要不被覆盖")
    }

    // MARK: - Recommend / Digest 触发

    func testRefreshGeneratesRecommendAndDigestWhenEnoughArticles() async {
        // 推荐展示数从 3 升 5：候选阈值同步抬到 5，因此种 5 篇才能同时触发推荐 + 日报
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, (1...5).map { makeRaw("https://a/\($0)", title: "T\($0)") })

        await service.refresh()

        XCTAssertEqual(ai.recommendCallCount, 1)
        XCTAssertEqual(ai.digestCallCount, 1)
        XCTAssertNotNil(service.dailyDigest)
        XCTAssertEqual(service.recommendedArticleIDs.count, 5)
    }

    func testRefreshSkipsDigestBelow3Articles() async {
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/1"), makeRaw("https://a/2")])

        await service.refresh()

        XCTAssertEqual(ai.digestCallCount, 0, "少于 3 篇有摘要的文章时不生成日报")
        XCTAssertEqual(ai.recommendCallCount, 0, "少于 5 篇时不生成推荐（2 < 3 < 5 自然满足）")
    }

    // MARK: - Force regenerate

    func testForceRegenerateRecommend() async {
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, (1...5).map { makeRaw("https://a/\($0)", title: "T\($0)") })
        await service.refresh()
        let before = ai.recommendCallCount

        await service.forceRegenerateRecommend()

        XCTAssertEqual(ai.recommendCallCount, before + 1)
    }

    func testForceRegenerateDigest() async {
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, (1...5).map { makeRaw("https://a/\($0)", title: "T\($0)") })
        await service.refresh()
        let before = ai.digestCallCount

        await service.forceRegenerateDigest()

        XCTAssertEqual(ai.digestCallCount, before + 1)
    }

    func testForceRegenerateRecommendNoAPIKey() async {
        prefs.apiKey = nil
        await service.forceRegenerateRecommend()
        if case .unavailable = service.aiAvailability {
            // OK
        } else {
            XCTFail("应为 unavailable")
        }
    }

    func testForceRegenerateRecommendBelow5Articles() async {
        // 候选阈值升 5 后，force regen 同样需 ≥ 5 篇才能调 AI
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, (1...4).map { makeRaw("https://a/\($0)", title: "T\($0)") })
        await service.refresh()
        let before = ai.recommendCallCount

        await service.forceRegenerateRecommend()
        XCTAssertEqual(ai.recommendCallCount, before, "少于 5 篇时不应调 AI")
    }

    // MARK: - Cleanup

    func testCleanupRemovesPreviousDayArticles() async {
        let feed = seedFeed("https://f1.com/feed")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let stale = Article(title: "old", url: "https://a/old", publishedAt: yesterday,
                            feedID: feed.id, feedTitle: feed.title)
        context.insert(stale)
        try? context.save()

        rss.setSuccess(feed.url, [makeRaw("https://a/new")])
        await service.refresh()

        let urls = fetchArticles().map(\.url)
        XCTAssertFalse(urls.contains("https://a/old"))
        XCTAssertTrue(urls.contains("https://a/new"))
    }

    // MARK: - Persistence

    func testRefreshPersistsDigest() async {
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, (1...3).map { makeRaw("https://a/\($0)", title: "T\($0)") })
        ai.digestProvider = { _ in "测试日报内容" }

        await service.refresh()

        XCTAssertEqual(prefs.digestContent, "测试日报内容")
        XCTAssertNotNil(prefs.digestDate)
        XCTAssertGreaterThan(prefs.digestArticleCount, 0)
    }

    func testRefreshHandlesAIErrors() async {
        // 推荐候选阈值升 5：失败路径也需种 ≥ 5 篇才能让 recommend 真正被调用并报错
        let feed = seedFeed("https://f1.com/feed")
        rss.setSuccess(feed.url, (1...5).map { makeRaw("https://a/\($0)", title: "T\($0)") })
        ai.recommendError = URLError(.timedOut)

        await service.refresh()
        // 推荐失败时 aiAvailability 应为 unavailable
        if case .unavailable = service.aiAvailability {
            // OK
        } else {
            XCTFail("推荐失败应记录为 unavailable")
        }
    }

    // MARK: - resetCrossedDayStateIfNeeded（跨日全量重置）

    func testCrossedDayResetRemovesYesterdayArticles() {
        let feed = seedFeed("https://f/feed")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        context.insert(Article(title: "old", url: "https://a/old", publishedAt: yesterday,
                               feedID: feed.id, feedTitle: feed.title))
        let today = Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(3600)
        context.insert(Article(title: "new", url: "https://a/new", publishedAt: today,
                               feedID: feed.id, feedTitle: feed.title))
        try? context.save()

        service.lastRefreshDate = yesterday
        service.resetCrossedDayStateIfNeeded()

        let urls = fetchArticles().map(\.url).sorted()
        XCTAssertEqual(urls, ["https://a/new"], "跨日时应清掉昨天的文章，保留今天的")
    }

    // 关键回归测试：跨日时 @Published 的 UI 状态必须被清空
    // 否则用户打开菜单仍会看到昨天的 digest / 推荐内容直到 refresh 完成
    func testCrossedDayResetClearsUIState() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        service.lastRefreshDate = yesterday
        service.dailyDigest = "昨天的摘要"
        service.recommendedArticleIDs = [UUID(), UUID()]
        service.lastDigestDate = yesterday
        service.lastRecommendDate = yesterday
        prefs.saveDigest(content: "昨天的摘要", date: yesterday)
        prefs.saveDigestArticleCount(5)
        prefs.saveRecommendArticleCount(5)

        service.resetCrossedDayStateIfNeeded()

        XCTAssertNil(service.dailyDigest, "@Published dailyDigest 必须被清空")
        XCTAssertEqual(service.recommendedArticleIDs, [], "推荐 ID 必须被清空")
        XCTAssertNil(service.lastDigestDate)
        XCTAssertNil(service.lastRecommendDate)
        XCTAssertNil(prefs.digestContent, "prefs 的 digest 必须被清空")
    }

    func testCrossedDayResetNoopWhenLastResetIsToday() {
        let feed = seedFeed("https://f/feed")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        context.insert(Article(title: "old", url: "https://a/old", publishedAt: yesterday,
                               feedID: feed.id, feedTitle: feed.title))
        try? context.save()

        // 新实现：用 lastResetCheckDate 而非 lastRefreshDate 做 guard
        // 这是修复"裸 refresh() 末尾写 lastRefreshDate 抹掉跨日信号"的关键
        service.lastResetCheckDate = Date()
        service.dailyDigest = "今天的摘要"
        service.resetCrossedDayStateIfNeeded()

        XCTAssertEqual(fetchArticles().map(\.url), ["https://a/old"], "同日不应触发清理")
        XCTAssertEqual(service.dailyDigest, "今天的摘要", "同日不应清 UI 状态")
    }

    /// 首次启动场景：lastResetCheckDate 为 nil 时应触发首次 reset
    /// 这是新逻辑相对旧逻辑（lastRefreshDate nil 时 noop）的语义改进：
    /// 首次启动如果旧库残留昨天文章，应当被清理掉，而不是等到下次 refresh
    func testCrossedDayResetFirstRunTriggersCleanup() {
        let feed = seedFeed("https://f/feed")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        context.insert(Article(title: "old", url: "https://a/old", publishedAt: yesterday,
                               feedID: feed.id, feedTitle: feed.title))
        try? context.save()

        XCTAssertNil(service.lastResetCheckDate, "首次启动 lastResetCheckDate 应为 nil")
        service.resetCrossedDayStateIfNeeded()

        XCTAssertEqual(fetchArticles().count, 0, "首次启动应清理旧库残留的昨天文章")
        XCTAssertNotNil(service.lastResetCheckDate, "执行后应 set lastResetCheckDate")
    }

    // refreshIfNeeded 入口同样触发跨日重置 —— 这是修复"打开菜单仍显示昨天 digest"的关键路径
    func testRefreshIfNeededTriggersCrossedDayReset() async {
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/new")])

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        service.lastRefreshDate = yesterday
        service.dailyDigest = "昨天的摘要"
        prefs.saveDigest(content: "昨天的摘要", date: yesterday)

        await service.refreshIfNeeded()

        // refreshIfNeeded → resetCrossedDayStateIfNeeded → 立即清空 dailyDigest
        // 紧随 refresh() 触发；本测试关注的是 "打开瞬间 UI 已切到空" 这步
        XCTAssertNil(prefs.digestContent, "prefs digest 应被跨日重置清空（即便 refresh 后未重新生成）")
    }
}
