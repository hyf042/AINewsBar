import Foundation

// 命名历史：此服务文件曾名为 ClaudeService.swift；类名 BailianService 自始至终未变

// MARK: - Errors

enum BailianError: Error, LocalizedError {
    case httpStatus(code: Int, bodySnippet: String)
    case malformedResponse(reason: String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body):
            return "HTTP \(code)：\(body)"
        case .malformedResponse(let reason):
            return "响应解析失败：\(reason)"
        }
    }
}

actor BailianService: AISummarizing {
    static let shared = BailianService()

    private let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    func testConnection(apiKey: String, model: String) async throws {
        _ = try await chat(prompt: "1", maxTokens: 1, apiKey: apiKey, modelOverride: model)
    }

    func generateSummary(title: String, content: String?, apiKey: String) async throws -> String {
        let prompt = Self.makeSummaryPrompt(title: title, content: content)
        return try await chat(prompt: prompt, maxTokens: 150, apiKey: apiKey)
    }

    func recommendArticles(_ articles: [(id: UUID, title: String, summary: String?)], apiKey: String) async throws -> [UUID] {
        guard articles.count >= 3 else { return articles.map(\.id) }
        let prompt = Self.makeRecommendPrompt(articles: articles)
        let response = try await chat(prompt: prompt, maxTokens: 20, apiKey: apiKey)
        return Self.parseRecommendResponse(response, totalCount: articles.count)
            .map { articles[$0 - 1].id }
    }

    func generateDigest(articleSummaries: [(title: String, summary: String)], apiKey: String) async throws -> String {
        let prompt = Self.makeDigestPrompt(summaries: articleSummaries)
        return try await chat(prompt: prompt, maxTokens: 300, apiKey: apiKey)
    }

    // MARK: - Prompt 构造（纯函数，可单测）

    static func makeSummaryPrompt(title: String, content: String?) -> String {
        """
        请用中文一句话（不超过50字）概括以下文章的核心内容，无论原文是何种语言，必须用中文回复：

        标题：\(title)
        内容：\(content?.prefix(1500) ?? "无正文")
        """
    }

    static func makeRecommendPrompt(articles: [(id: UUID, title: String, summary: String?)]) -> String {
        let list = articles.prefix(50).enumerated()
            .map { i, article -> String in
                var line = "\(i + 1). \(article.title)"
                if let s = article.summary { line += "｜\(s)" }
                return line
            }
            .joined(separator: "\n")

        return """
        以下是今日 AI 资讯列表（标题｜摘要），请从中挑选3篇最值得阅读的文章。\
        只返回序号，用英文逗号分隔，不要其他内容，例如：2,7,15

        \(list)
        """
    }

    static func makeDigestPrompt(summaries: [(title: String, summary: String)]) -> String {
        let items = summaries.prefix(20)
            .map { "- \($0.title)｜\($0.summary)" }
            .joined(separator: "\n")

        return """
        以下是今日 AI 资讯（标题｜摘要），请用中文写 2-3 句话概括今日最重要的 AI 进展，必须用中文回复：

        \(items)
        """
    }

    // MARK: - 序号解析（纯函数，可单测）

    /// 支持的分隔符：英文逗号 / 中文逗号 / 顿号 / 空格 / 换行 / Tab
    static let indexSeparators = CharacterSet(charactersIn: ",，、 \n\t")

    /// 解析模型返回的序号串。返回 1-based 序号数组，保序去重，越界过滤，最多 3 个。
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
            if result.count == 3 { break }
        }
        return result
    }

    // MARK: - HTTP

    private func chat(prompt: String, maxTokens: Int, apiKey: String, modelOverride: String? = nil) async throws -> String {
        let activeModel = modelOverride ?? PreferencesService.shared.getModel()
        let body: [String: Any] = [
            "model": activeModel,
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

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
