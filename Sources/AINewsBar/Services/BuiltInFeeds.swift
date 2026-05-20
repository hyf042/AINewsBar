import Foundation

enum BuiltInFeeds {
    static let all: [(title: String, url: String)] = [
        // 官方研究博客
        ("OpenAI News",           "https://openai.com/news/rss.xml"),
        ("Google DeepMind",       "https://deepmind.google/blog/rss.xml"),
        ("Hugging Face Blog",     "https://huggingface.co/blog/feed.xml"),
        // 科技媒体 AI 专栏
        ("TechCrunch AI",         "https://techcrunch.com/category/artificial-intelligence/feed/"),
        ("The Verge AI",          "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml"),
        ("Ars Technica AI",       "https://arstechnica.com/ai/feed"),
        ("The Decoder",           "https://the-decoder.com/feed/"),
        ("MIT Technology Review", "https://www.technologyreview.com/topic/artificial-intelligence/feed"),
        ("VentureBeat AI",        "https://venturebeat.com/category/ai/feed/"),
        // 日报 / 速读
        ("TLDR AI",               "https://tldr.tech/api/rss/ai"),
        // 中文
        ("量子位",                  "https://www.qbitai.com/feed"),
    ]

    static func makeFeeds() -> [Feed] {
        all.map { Feed(title: $0.title, url: $0.url, isBuiltIn: true) }
    }
}
