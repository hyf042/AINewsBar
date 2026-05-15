import Foundation

actor OpenAIService {
    static let shared = OpenAIService()

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func generateSummary(for article: Article, apiKey: String) async throws -> String {
        let prompt = """
        用一句话（不超过50字）概括以下文章的核心内容，语言简洁直接：

        标题：\(article.title)
        内容：\(article.content?.prefix(500) ?? "无正文")
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 100,
            "temperature": 0.3
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
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
