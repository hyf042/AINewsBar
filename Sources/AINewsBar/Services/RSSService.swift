import Foundation
import FeedKit

// Sendable struct for cross-actor data transfer.
// publishedAt 为 Optional —— RSS 源缺失发布时间时不伪造为 "现在"，由调用方决定是否入库 (P11)
struct RawArticle: Sendable {
    let title: String
    let url: String
    let content: String?
    let publishedAt: Date?
}

enum RSSFetchError: Error, LocalizedError {
    case httpStatus(code: Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "RSS HTTP \(code)"
        }
    }
}

actor RSSService: RSSFetching {
    static let shared = RSSService()

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 AINewsBar/2.0"

    private let session: URLSession

    init(timeout: TimeInterval = 10) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    init(session: URLSession) {
        self.session = session
    }

    func fetchRawArticles(feedURL: String) async throws -> [RawArticle] {
        // P2 第六轮 review：RSS 源 URL 是外部输入（用户输 / RSS 源管理后端 / migration），
        // 仅允许 http/https。拒绝 file://、javascript:、shell: 等 scheme。
        guard let url = URL(string: feedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw URLError(.unsupportedURL)
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw RSSFetchError.httpStatus(code: http.statusCode)
        }
        let parser = FeedParser(data: data)
        let parsedFeed = try parser.parse().get()
        return Self.extract(from: parsedFeed)
    }

    static func extract(from feed: FeedKit.Feed) -> [RawArticle] {
        switch feed {
        case .rss(let rss):
            return rss.items?.compactMap { item in
                guard let title = item.title, let link = item.link else { return nil }
                return RawArticle(title: title, url: link, content: item.description, publishedAt: item.pubDate)
            } ?? []
        case .atom(let atom):
            return atom.entries?.compactMap { entry in
                guard let title = entry.title,
                      let link = preferredAtomLink(entry.links) else { return nil }
                return RawArticle(title: title, url: link, content: entry.summary?.value,
                                  publishedAt: entry.published ?? entry.updated)
            } ?? []
        case .json(let json):
            return json.items?.compactMap { item in
                guard let title = item.title, let link = item.url else { return nil }
                return RawArticle(title: title, url: link, content: item.contentText, publishedAt: item.datePublished)
            } ?? []
        }
    }

    private static func preferredAtomLink(_ links: [AtomFeedEntryLink]?) -> String? {
        guard let links else { return nil }

        let alternateHTML = links.first { link in
            guard link.attributes?.href != nil else { return false }
            let rel = link.attributes?.rel?.lowercased()
            let type = link.attributes?.type?.lowercased()
            let isAlternate = rel == nil || rel == "alternate"
            let isHTML = type == nil || type == "text/html" || type == "application/xhtml+xml"
            return isAlternate && isHTML
        }
        if let href = alternateHTML?.attributes?.href { return href }

        let alternate = links.first { link in
            guard link.attributes?.href != nil else { return false }
            let rel = link.attributes?.rel?.lowercased()
            return rel == nil || rel == "alternate"
        }
        return alternate?.attributes?.href ?? links.first(where: { $0.attributes?.href != nil })?.attributes?.href
    }
}
