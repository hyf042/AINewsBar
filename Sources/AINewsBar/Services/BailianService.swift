import Foundation

// 命名历史：此服务文件曾名为 ClaudeService.swift；类名 BailianService 自始至终未变

// MARK: - Errors

enum BailianError: Error, LocalizedError {
    case httpStatus(code: Int, bodySnippet: String)
    case malformedResponse(reason: String)
    case insufficientCandidates(count: Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body):
            return "HTTP \(code)：\(body)"
        case .malformedResponse(let reason):
            return "响应解析失败：\(reason)"
        case .insufficientCandidates(let count):
            return "候选不足（仅 \(count) 篇，至少需要 5 篇）"
        }
    }
}

actor BailianService: AISummarizing {
    static let shared = BailianService()

    private let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
    private let session: URLSession

    init(timeout: TimeInterval = 30) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    func testConnection(apiKey: String, model: String) async throws {
        _ = try await chat(prompt: "1", maxTokens: 1, apiKey: apiKey, model: model)
    }

    // MARK: - AISummarizing 新签名（per-cat prompt）

    func generateSummary(
        title: String, content: String?,
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (summary: String, usage: UsageInfo) {
        let prompt = Self.makeSummaryPrompt(title: title, content: content, category: category)
        let (text, usage) = try await chat(prompt: prompt, maxTokens: 150, apiKey: apiKey, model: model)
        return (text, usage)
    }

    func recommendArticles(
        _ items: [ArticleSnapshot.Item],
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (ids: [UUID], usage: UsageInfo) {
        // 候选不足时显式抛错，让 caller 走 aiAvailability=.unavailable 路径
        // 不再退化为返回全部 id（旧逻辑会把含 nil-summary 的退化数据当推荐结果）
        guard items.count >= 5 else {
            throw BailianError.insufficientCandidates(count: items.count)
        }
        let prompt = Self.makeRecommendPrompt(items: items, category: category)
        // maxTokens 30：5 个 1-2 位数序号 + 4 个分隔符 ≈ 14 字符；留 ~2 倍冗余兼容模型偶发啰嗦
        let (response, usage) = try await chat(prompt: prompt, maxTokens: 30, apiKey: apiKey, model: model)
        let ids = Self.parseRecommendResponse(response, totalCount: items.count)
            .map { items[$0 - 1].id }
        return (ids, usage)
    }

    func generateDigest(
        items: [ArticleSnapshot.Item],
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (content: String, usage: UsageInfo) {
        let prompt = Self.makeDigestPrompt(items: items, category: category)
        let (text, usage) = try await chat(prompt: prompt, maxTokens: 300, apiKey: apiKey, model: model)
        return (text, usage)
    }

    // MARK: - Filter Stage (v2-multi-category)

    /// max_tokens=10 输出截断保护；temperature=0.1 让分类任务输出稳定
    func classifyArticle(
        title: String, description: String, prompt: String,
        apiKey: String, model: String
    ) async throws -> (accepted: Bool, usage: UsageInfo) {
        let fullPrompt = Self.makeFilterPrompt(
            template: prompt, title: title, description: description
        )
        let (response, usage) = try await chat(
            prompt: fullPrompt, maxTokens: 10, apiKey: apiKey, model: model,
            temperature: 0.1
        )
        guard let accepted = Self.parseFilterResponse(response) else {
            // 解析失败抛错让 caller 走 filterFailCount++ 路径
            throw BailianError.malformedResponse(reason: "filter 响应无法解析：\(response.prefix(30))")
        }
        return (accepted, usage)
    }

    // MARK: - Prompt 构造（纯函数，可单测）

    /// AI 摘要 prompt。per-cat 文案差异化（关注点、术语）；通用约束：中文 + 50 字内 + 纯文本。
    /// category 默认 .ai 方便测试调用（生产调用必显式传）。
    static func makeSummaryPrompt(
        title: String, content: String?, category: AINewsBar.Category = .ai
    ) -> String {
        let focus: String
        switch category {
        case .ai:
            focus = "AI / 科技资讯的核心内容（如新模型发布、能力突破、关键观点）"
        case .earnings:
            focus = "财经资讯的核心内容（如财报数据、营收/EPS、业绩指引、关键决策）"
        case .news:
            focus = "新闻的核心内容（如时政事件、社会动态、关键决策）"
        }
        return """
        请用中文一句话（不超过50字）概括以下\(focus)，无论原文是何种语言，必须用中文回复，请用纯文本回复，不要使用 markdown 语法（不要使用 **、##、- 等符号）：

        标题：\(title)
        内容：\(content?.prefix(1500) ?? "无正文")
        """
    }

    /// AI 推荐 prompt。per-cat 关注角度差异化（AI 从业者 / 投资者 / 关心时事的读者）。
    /// category 默认 .ai 方便测试调用（生产调用必显式传）。
    static func makeRecommendPrompt(
        items: [ArticleSnapshot.Item], category: AINewsBar.Category = .ai
    ) -> String {
        let list = items.prefix(50).enumerated()
            .map { i, item -> String in
                var line = "\(i + 1). \(item.title)"
                if let s = item.summary { line += "｜\(s)" }
                return line
            }
            .joined(separator: "\n")

        let intro: String
        switch category {
        case .ai:
            intro = "以下是今日 AI 资讯列表（标题｜摘要），请从中挑选 5 篇最值得 AI 从业者阅读的文章"
        case .earnings:
            intro = "以下是今日财经资讯列表（标题｜摘要），请从中挑选 5 篇对个人投资者最有参考价值的文章（重点是知名公司财报、业绩超预期/不达预期、重要并购/人事）"
        case .news:
            intro = "以下是今日新闻列表（标题｜摘要），请从中挑选 5 篇最重要的新闻（重点是国际国内重大事件、影响广泛的决策）"
        }
        return """
        \(intro)，并按推荐度由高到低排序。\
        只返回序号，用英文逗号分隔，不要其他内容，例如：7,2,15,9,4

        \(list)
        """
    }

    /// AI 日报 prompt。per-cat 总结角度差异化。
    /// category 默认 .ai 方便测试调用（生产调用必显式传）。
    static func makeDigestPrompt(
        items: [ArticleSnapshot.Item], category: AINewsBar.Category = .ai
    ) -> String {
        // 防御性：nil-summary 项跳过；caller 通常已传 summarized 子集
        let lines = items.prefix(20).compactMap { item -> String? in
            guard let s = item.summary else { return nil }
            return "- \(item.title)｜\(s)"
        }
        .joined(separator: "\n")

        let intro: String
        switch category {
        case .ai:
            intro = "以下是今日 AI 资讯（标题｜摘要），请用中文写 2-3 句话概括今日最重要的 AI 进展"
        case .earnings:
            intro = "以下是今日财经资讯（标题｜摘要），请用中文写 2-3 句话概括今日最重要的财报与公司动态，重点关注哪些公司发布业绩、关键数据如何"
        case .news:
            intro = "以下是今日新闻（标题｜摘要），请用中文写 2-3 句话概括今日最重要的国际国内动态"
        }
        return """
        \(intro)，必须用中文回复，请用纯文本回复，不要使用 markdown 语法（不要使用 **、##、- 等符号）：

        \(lines)
        """
    }

    /// Filter prompt 装配。把 CategoryConfig.filterPrompt 模板与文章 title/description 拼接。
    /// 模板中 `<title>` 和 `<description>` 是占位符，此处用实际内容替换。
    static func makeFilterPrompt(template: String, title: String, description: String) -> String {
        let truncatedDesc = String(description.prefix(200))
        return template
            .replacingOccurrences(of: "<title>", with: title)
            .replacingOccurrences(of: "<description>", with: truncatedDesc)
    }

    // MARK: - 序号解析（纯函数，可单测）

    /// 支持的分隔符：英文逗号 / 中文逗号 / 顿号 / 空格 / 换行 / Tab
    static let indexSeparators = CharacterSet(charactersIn: ",，、 \n\t")

    /// 解析模型返回的序号串。返回 1-based 序号数组，保序去重，越界过滤，最多 5 个。
    /// 模型按推荐度由高到低返回，因此保序即推荐度排序。
    static func parseRecommendResponse(_ response: String, totalCount: Int) -> [Int] {
        let parts = response.components(separatedBy: indexSeparators)
        var seen = Set<Int>()
        var result: [Int] = []
        for part in parts {
            guard let n = Int(part.trimmingCharacters(in: .whitespaces)),
                  n >= 1, n <= totalCount,
                  !seen.contains(n) else { continue }
            seen.insert(n)
            result.append(n)
            if result.count == 5 { break }
        }
        return result
    }

    /// Filter 响应解析：首字符匹配 "是" / "否"。
    /// 容错："是的，..." / "否，因为..." / 前缀空白都正确解析。
    /// 返回 nil = 解析失败（空响应 / 首字符非 是/否）→ caller 走 retry 路径。
    static func parseFilterResponse(_ response: String) -> Bool? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        switch first {
        case "是": return true
        case "否": return false
        default:   return nil
        }
    }

    /// 从 DashScope 响应 JSON 中提取 usage；缺失/异常返回 .zero（不影响主流程）。
    static func parseUsage(from json: [String: Any]?) -> UsageInfo {
        guard let usage = json?["usage"] as? [String: Any] else { return .zero }
        let input = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int) ?? 0
        return UsageInfo(inputTokens: max(0, input), outputTokens: max(0, output))
    }

    // MARK: - HTTP

    private func chat(
        prompt: String, maxTokens: Int, apiKey: String, model: String,
        temperature: Double = 0.3
    ) async throws -> (content: String, usage: UsageInfo) {
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens,
            "temperature": temperature
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let snippet = String(String(data: data, encoding: .utf8)?.prefix(200) ?? "")
            Log.write("[Bailian] HTTP \(status): \(snippet)")
            throw BailianError.httpStatus(code: status, bodySnippet: snippet)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw BailianError.malformedResponse(reason: "missing choices[0].message.content")
        }

        let usage = Self.parseUsage(from: json)
        return (content.trimmingCharacters(in: .whitespacesAndNewlines), usage)
    }
}
