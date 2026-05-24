import Testing
@testable import AINewsBar

@Suite("MarkdownStripper")
struct MarkdownStripperTests {

    @Test("** 粗体 → 去标记保留内容")
    func stripsDoubleAsteriskBold() {
        #expect(MarkdownStripper.strip("**今日重要进展**") == "今日重要进展")
        #expect(MarkdownStripper.strip("前缀**中间**后缀") == "前缀中间后缀")
    }

    @Test("__ 粗体 → 去标记保留内容")
    func stripsDoubleUnderscoreBold() {
        #expect(MarkdownStripper.strip("__强调内容__") == "强调内容")
    }

    @Test("行首 # / ## / ### 标题前缀整段去除")
    func stripsHeadingPrefix() {
        #expect(MarkdownStripper.strip("# 一级标题") == "一级标题")
        #expect(MarkdownStripper.strip("## 二级标题") == "二级标题")
        #expect(MarkdownStripper.strip("### 三级标题") == "三级标题")
        #expect(MarkdownStripper.strip("###### 六级标题") == "六级标题")
    }

    @Test("行首列表符号 - / * / + 保留（中文摘要的合理层次表达）")
    func keepsListMarkers() {
        #expect(MarkdownStripper.strip("- 第一点") == "- 第一点")
        #expect(MarkdownStripper.strip("* 第二点") == "* 第二点")
        #expect(MarkdownStripper.strip("+ 第三点") == "+ 第三点")
    }

    @Test("单个 * 强调不动（避免误伤普通文本）")
    func keepsSingleAsterisk() {
        #expect(MarkdownStripper.strip("*emphasis*") == "*emphasis*")
        #expect(MarkdownStripper.strip("文中 * 号") == "文中 * 号")
    }

    @Test("空串与多行综合场景")
    func handlesEdgeCasesAndCombination() {
        #expect(MarkdownStripper.strip("") == "")
        #expect(MarkdownStripper.strip("纯文本无变化") == "纯文本无变化")

        let input = "**今日重要进展**：\n# 头条新闻\n- 第一点\n## 次级标题\n__关键__内容"
        let expected = "今日重要进展：\n头条新闻\n- 第一点\n次级标题\n关键内容"
        #expect(MarkdownStripper.strip(input) == expected)
    }
}
