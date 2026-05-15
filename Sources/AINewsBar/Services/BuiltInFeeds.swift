import Foundation

enum BuiltInFeeds {
    static let all: [(title: String, url: String)] = [
        ("OpenAI Blog", "https://openai.com/blog/rss.xml"),
        ("Anthropic News", "https://www.anthropic.com/rss.xml"),
        ("Google DeepMind", "https://deepmind.google/blog/rss.xml"),
        ("The Batch (DeepLearning.AI)", "https://www.deeplearning.ai/the-batch/feed/"),
        ("机器之心", "https://www.jiqizhixin.com/rss"),
        ("36Kr AI", "https://36kr.com/feed"),
    ]

    static func makeFeeds() -> [Feed] {
        all.map { Feed(title: $0.title, url: $0.url, isBuiltIn: true) }
    }
}
