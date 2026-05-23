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

    func testConnection(apiKey: String, model: String) async throws {
        _ = try await chat(prompt: "1", maxTokens: 1, apiKey: apiKey, model: model)
    }

    func generateSummary(title: String, content: String?, apiKey: String, model: String)
        async throws -> (summary: String, usage: UsageInfo)
    {
        let prompt = Self.makeSummaryPrompt(title: title, content: content)
        let (text, usage) = try await chat(prompt: prompt, maxTokens: 150, apiKey: apiKey, model: model)
        return (text, usage)
    }

    func recommendArticles(_ items: [ArticleSnapshot.Item], apiKey: String, model: String)
        async throws -> (ids: [UUID], usage: UsageInfo)
    {
        // 候选不足时显式抛错，让 caller 走 aiAvailability=.unavailable 路径
        // 不再退化为返回全部 id（旧逻辑会把含 nil-summary 的退化数据当推荐结果）
        guard items.count >= 5 else {
            throw BailianError.insufficientCandidates(count: items.count)
        }
        let prompt = Self.makeRecommendPrompt(items: items)
        // maxTokens 30：5 个 1-2 位数序号 + 4 个分隔符 ≈ 14 字符；留 ~2 倍冗余兼容模型偶发啰嗦
        let (response, usage) = try await chat(prompt: prompt, maxTokens: 30, apiKey: apiKey, model: model)
        let ids = Self.parseRecommendResponse(response, totalCount: items.count)
            .map { items[$0 - 1].id }
        return (ids, usage)
    }

    func generateDigest(items: [ArticleSnapshot.Item], apiKey: String, model: String)
        async throws -> (content: String, usage: UsageInfo)
    {
        let prompt = Self.makeDigestPrompt(items: items)
        let (text, usage) = try await chat(prompt: prompt, maxTokens: 300, apiKey: apiKey, model: model)
        return (text, usage)
    }

    // MARK: - Prompt 构造（纯函数，可单测）

    static func makeSummaryPrompt(title: String, content: String?) -> String {
        """
        请用中文一句话（不超过50字）概括以下文章的核心内容，无论原文是何种语言，必须用中文回复：

        标题：\(title)
        内容：\(content?.prefix(1500) ?? "无正文")
        """
    }

    static func makeRecommendPrompt(items: [ArticleSnapshot.Item]) -> String {
        let list = items.prefix(50).enumerated()
            .map { i, item -> String in
                var line = "\(i + 1). \(item.title)"
                if let s = item.summary { line += "｜\(s)" }
                return line
            }
            .joined(separator: "\n")

        return """
        以下是今日 AI 资讯列表（标题｜摘要），请从中挑选 5 篇最值得阅读的文章，\
        并按推荐度由高到低排序。\
        只返回序号，用英文逗号分隔，不要其他内容，例如：7,2,15,9,4

        \(list)
        """
    }

    static func makeDigestPrompt(items: [ArticleSnapshot.Item]) -> String {
        // 防御性：nil-summary 项跳过；caller 通常已传 summarized 子集
        let lines = items.prefix(20).compactMap { item -> String? in
            guard let s = item.summary else { return nil }
            return "- \(item.title)｜\(s)"
        }
        .joined(separator: "\n")

        return """
        以下是今日 AI 资讯（标题｜摘要），请用中文写 2-3 句话概括今日最重要的 AI 进展，必须用中文回复：

        \(lines)
        """
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

    /// 从 DashScope 响应 JSON 中提取 usage；缺失/异常返回 .zero（不影响主流程）。
    static func parseUsage(from json: [String: Any]?) -> UsageInfo {
        guard let usage = json?["usage"] as? [String: Any] else { return .zero }
        let input = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int) ?? 0
        return UsageInfo(inputTokens: max(0, input), outputTokens: max(0, output))
    }

    // MARK: - HTTP

    private func chat(prompt: String, maxTokens: Int, apiKey: String, model: String)
        async throws -> (content: String, usage: UsageInfo)
    {
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens,
            "temperature": 0.3
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

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
