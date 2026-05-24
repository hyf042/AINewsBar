import Foundation

/// 每个分类的可配置项：filter 是否启用 + filter prompt + 推荐篇数。
/// 不进 prompt 文案（summary / digest / recommend prompt 由 BailianService 静态方法内部 switch
/// 选择，避免 prompt 细节外泄到 Models 层）。
///
/// 硬编码在源码（个人工具不需要 UI 编辑配置；prompt 调整可走 git diff 追溯）。
struct CategoryConfig: Sendable {
    let category: Category

    /// AI Filter 提示词。nil 表示该 cat 不跑 filter（入库时 accepted 直接为 true）。
    /// first release：仅财报启用；新闻预留；AI 永远 nil。
    let filterPrompt: String?

    /// AI 推荐挑选篇数。默认 5（与 BailianService.recommendArticles 现有 5 篇硬编码对齐）。
    let recommendCount: Int

    /// 全部内置配置；以 Category 为 key。运行时通过 `CategoryConfig.for(_:)` 查询。
    static let all: [Category: CategoryConfig] = [
        .ai: CategoryConfig(
            category: .ai,
            filterPrompt: nil,
            recommendCount: 5
        ),
        .earnings: CategoryConfig(
            category: .earnings,
            filterPrompt: Self.earningsFilterPrompt,
            recommendCount: 5
        ),
        .news: CategoryConfig(
            category: .news,
            filterPrompt: nil,  // first release 不配 filter，待 30 天后视实际噪声决定
            recommendCount: 5
        ),
    ]

    /// 取指定 cat 的配置。caseIterable 保证查无返回 fatalError；调用方应直接信任。
    static func `for`(_ category: Category) -> CategoryConfig {
        guard let config = all[category] else {
            // 不可达：Category.allCases 与 all dict 必然同步
            fatalError("CategoryConfig 缺失 \(category) 配置；检查 CategoryConfig.all 初始化")
        }
        return config
    }

    // MARK: - Filter Prompts（定稿）

    /// 财报 cat filter prompt。判定文章是否属于"公司财报类"。
    /// 输出约束：纯 "是"/"否"（max_tokens=10 截断保护；parseFilterResponse 首字符匹配 + 容错）。
    private static let earningsFilterPrompt = """
        判断下列文章是否属于"公司财报类"。

        通过条件（任一即通过）：
        - 单家公司的财报发布、业绩预告
        - 营收 / EPS / 毛利率 / 业绩指引
        - 重要并购、股东大会、重要人事变动

        拒绝条件：
        - 宏观经济、行业综述
        - 第三方分析、市场点评、政策解读
        - 单纯股价涨跌、技术分析

        标题：<title>
        描述：<description>

        仅回复"是"或"否"，不要其他内容。
        """
}
