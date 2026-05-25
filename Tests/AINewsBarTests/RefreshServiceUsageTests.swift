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

    /// non-credential 类型的 unavailable 不应被 applyCredentialChange 误清。
    /// 例如"摘要调用多数失败"，与 credential 无关，重置反而掩盖真实问题。
    /// 实测：applyCredentialChange 把所有 .unavailable → .unknown，再各 cat 跑
    /// refresh。如果没有 feeds（本测试设定）AI pipeline 不会跑，aiAvailability
    /// 会保持 .unknown —— 这与"被 credential 路径错误覆盖业务错误"等价。
    /// 这是已知 trade-off：保守清空让后续 refresh 重判，避免硬编码"哪些 reason 是 credential"。
    func testApplyCredentialChangeResetsAnyUnavailableToUnknown() async {
        prefs.apiKey = "key"
        service._testMutate(for: .ai) {
            $0.aiAvailability = .unavailable("摘要调用多数失败 (3/3)")
        }

        await service.applyCredentialChange()

        // 因 .ai cat 无 enabled feed，refresh 不会重设；此处验证至少不再 stale
        // 残留 "摘要调用多数失败" 这条 — 等下次真实 refresh 会重判
        if case .unavailable(let reason) = service.state(for: .ai).aiAvailability {
            XCTAssertFalse(reason.contains("摘要调用多数失败"),
                           "applyCredentialChange 后旧业务错误仍残留")
        }
    }
}
