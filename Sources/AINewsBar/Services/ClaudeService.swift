import Foundation

actor BailianService {
    static let shared = BailianService()

    private let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    func testConnection(apiKey: String, model: String) async throws {
        _ = try await chat(prompt: "1", maxTokens: 1, apiKey: apiKey, modelOverride: model)
    }

    func generateSummary(for article: Article, apiKey: String) async throws -> String {
        let prompt = """
        请用中文一句话（不超过50字）概括以下文章的核心内容，无论原文是何种语言，必须用中文回复：

        标题：\(article.title)
        内容：\(article.content?.prefix(500) ?? "无正文")
        """
        return try await chat(prompt: prompt, maxTokens: 150, apiKey: apiKey)
    }

    // 返回推荐文章的索引（0-based），从列表中挑选3篇
    func recommendArticles(_ articles: [(id: UUID, title: String, summary: String?)], apiKey: String) async throws -> [UUID] {
        guard articles.count >= 3 else { return articles.map(\.id) }

        let list = articles.prefix(50).enumerated()
            .map { i, article -> String in
                var line = "\(i + 1). \(article.title)"
                if let s = article.summary { line += "｜\(s)" }
                return line
            }
            .joined(separator: "\n")

        let prompt = """
        以下是今日 AI 资讯列表（标题｜摘要），请从中挑选3篇最值得阅读的文章。\
        只返回序号，用英文逗号分隔，不要其他内容，例如：2,7,15

        \(list)
        """

        let response = try await chat(prompt: prompt, maxTokens: 20, apiKey: apiKey)

        // 解析 "2,7,15" 格式
        let indices = response
            .components(separatedBy: CharacterSet(charactersIn: ",，、 "))
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 >= 1 && $0 <= articles.count }
            .prefix(3)
            .map { articles[$0 - 1].id }

        return Array(indices)
    }

    func generateDigest(articleSummaries: [(title: String, summary: String)], apiKey: String) async throws -> String {
        let items = articleSummaries.prefix(20)
            .map { "- \($0.title)" }
            .joined(separator: "\n")

        let prompt = """
        以下是今日 AI 资讯标题列表，请用中文写 2-3 句话概括今日最重要的 AI 进展，必须用中文回复：

        \(items)
        """
        return try await chat(prompt: prompt, maxTokens: 300, apiKey: apiKey)
    }

    private func chat(prompt: String, maxTokens: Int, apiKey: String, modelOverride: String? = nil) async throws -> String {
        let activeModel = modelOverride ?? KeychainService.shared.getModel()
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
            let body = String(data: data, encoding: .utf8) ?? ""
            Log.write("[Bailian] HTTP error: \(body.prefix(200))")
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
