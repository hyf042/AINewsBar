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

        // 推荐候选阈值升 5：种 ≥ 5 篇文章确保推荐 + 日报都被触发
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, (1...5).map { makeRaw("https://a/\($0)") })

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

        let availability = service.state(for: .ai).aiAvailability
        if case .unavailable = availability {
            // pass
        } else {
            XCTFail("expected .unavailable, got \(availability)")
        }
    }

    func testSummaryHTTP401SetsGlobalInvalidAPIKey() async {
        ai.summaryError = BailianError.httpStatus(code: 401, bodySnippet: "invalid api key")
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/1")])

        await service.refresh()

        XCTAssertEqual(service.globalAIError, .invalidAPIKey)
    }

    func testSuccessfulSummaryClearsPreviousGlobalAIError() async {
        service.globalAIError = .networkUnreachable
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, [makeRaw("https://a/1")])

        await service.refresh()

        XCTAssertNil(service.globalAIError)
    }

    func testRefreshRecordsRecommendFailure() async {
        struct StubErr: Error {}
        ai.recommendError = StubErr()
        // 推荐候选阈值升 5：种 ≥ 5 篇才会真正进入 AI 调用并报错
        let feed = seedFeed("https://f/feed")
        rss.setSuccess(feed.url, (1...5).map { makeRaw("https://a/\($0)") })

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

    // MARK: - applyCredentialChange (onboarding 断点修复)

    /// 模拟 onboarding 断点场景：
    /// 1. 首启无 API Key → refresh 跑到 AI 段失败，留下 globalAIError + per-cat unavailable
    /// 2. 用户填 key 测试成功 → applyCredentialChange 必须清 error + 重新触发各 cat refresh
    func testApplyCredentialChangeClearsErrorsAndTriggersAllCats() async {
        // Step 1: 无 key 时，service 状态被预置为"credential 失败"模式
        prefs.apiKey = nil
        service.globalAIError = .invalidAPIKey
        for cat in AINewsBar.Category.allCases {
            service._testMutate(for: cat) {
                $0.aiAvailability = .unavailable("未配置 API Key")
                $0.lastRefreshDate = Date()  // 模拟 RSS 段已经更新过
            }
        }

        // Step 2: 用户填 key + 设置页测试成功 → applyCredentialChange
        prefs.apiKey = "new-valid-key"
        await service.applyCredentialChange()

        // global error 已清
        XCTAssertNil(service.globalAIError)
        // 三 cat 的 credential-related unavailable 不再 stale；refresh 触发后
        // 至少要么 .available 要么真的因其他原因 .unavailable，但绝不能仍是
        // "未配置 API Key" 这条
        for cat in AINewsBar.Category.allCases {
            if case .unavailable(let reason) = service.state(for: cat).aiAvailability {
                XCTAssertFalse(reason.contains("未配置 API Key"),
                               "[\(cat.rawValue)] applyCredentialChange 后仍残留 credential 错误：\(reason)")
            }
        }
    }

    /// non-credential unavailable（如"摘要调用多数失败"/"摘要保存失败"/"数据库查询失败"）
    /// 不应被 applyCredentialChange 误清。
    /// 这些是真实业务错误，与 credential 无关，重置反而让 UI 失去"为什么 AI 不可用"信号。
    /// 第六轮 review 精确化：仅当 reason 完全等于 `missingCredentialReason` 才清。
    func testApplyCredentialChangePreservesNonCredentialUnavailable() async {
        prefs.apiKey = "key"
        let businessError = "摘要调用多数失败 (3/3)"
        service._testMutate(for: .ai) {
            $0.aiAvailability = .unavailable(businessError)
        }

        await service.applyCredentialChange()

        // refresh 无 enabled feed 不会重设，应保留业务 reason；如果 reason 被误清
        // 成 .unknown 表示精确匹配失效，会掩盖真实业务问题
        guard case .unavailable(let reason) = service.state(for: .ai).aiAvailability else {
            XCTFail("expected non-credential .unavailable to be preserved, got \(service.state(for: .ai).aiAvailability)")
            return
        }
        XCTAssertEqual(reason, businessError,
                       "非 credential 业务错误必须保留，不能被 applyCredentialChange 清掉")
    }

    /// credential reason 必须精确匹配 RefreshService.missingCredentialReason
    /// 才会被 applyCredentialChange 重置；保证 ensureCredentials 与 applyCredentialChange
    /// 两端 reason 不漂移。
    func testApplyCredentialChangeClearsExactCredentialReason() async {
        prefs.apiKey = "key"
        service._testMutate(for: .ai) {
            $0.aiAvailability = .unavailable(RefreshService.missingCredentialReason)
        }

        await service.applyCredentialChange()

        if case .unavailable(let reason) = service.state(for: .ai).aiAvailability {
            XCTAssertNotEqual(reason, RefreshService.missingCredentialReason,
                              "credential reason 必须被清除")
        }
    }
}
