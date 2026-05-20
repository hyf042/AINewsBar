# AINewsBar — Claude 工作记录

## 项目背景

macOS 菜单栏 AI 资讯阅读器。通过 `/grill-me` 技术访谈定义设计决策，从零完成全部实现（截至 2026-05-20 所有功能已完成并可运行）。

**位置：** `/Users/hyf042/Projects/AINewsBar`  
**性质：** 个人工具，Swift Package Manager，macOS 14+，无 Xcode project 文件

---

## 设计决策记录

| 维度 | 决策 | 理由 |
|------|------|------|
| 应用类型 | macOS 菜单栏（MenuBarExtra） | RSS 需后台刷新，WidgetKit 刷新策略不适合 |
| 技术栈 | Swift + SwiftUI + macOS 14+ | 原生体验，MenuBarExtra 成熟，SwiftData 集成顺畅 |
| 数据来源 | 内置精选源 + 用户自定义 RSS | 开箱即用 + 灵活扩展 |
| UI 布局 | 文章列表 → AI 推荐 → 今日摘要 | 操作项优先，静态阅读内容置后 |
| 刷新策略 | 后台每小时 + 打开时按需（超 30 分钟触发） | 兼顾实时性和资源效率 |
| 已读状态 | 两个独立 @Query（未读在前 + 已读在后），标题色区分 | List Section header 有系统背景色问题，改用普通行充当分隔 |
| 文章点击 | 浏览器打开原文 + AI 一句话简介 | 符合用户预期 |
| AI 摘要服务 | 阿里云百炼 DashScope，模型可配置（默认 qwen3.6-plus） | 原设计 qwen-plus，升级为新模型列表；支持千问/智谱/Kimi/MiniMax |
| 密钥存储 | UserDefaults（`com.ainewsbar.claude-api-key` / `com.ainewsbar.model`） | ad-hoc 签名避免弹授权窗口 |
| 数据持久化 | SwiftData（Feed / Article）+ UserDefaults（日报内容 + 生成时间） | 日报跨重启保留，次日自动失效 |
| 分发方式 | 仅自用，ad-hoc 签名 | 无需公证和 App Store 审核 |
| AI 调用优化 | 推荐：有新文章或列表空才生成；日报：有新文章且距上次 >3h 才重新生成 | 避免无意义 API 消耗 |

---

## 构建 & 运行

```bash
cd /Users/hyf042/Projects/AINewsBar
swift build
pkill -x AINewsBar; sleep 1
cp .build/debug/AINewsBar build/AINewsBar.app/Contents/MacOS/AINewsBar
codesign --sign - --force build/AINewsBar.app
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

> **不要用 `open` 命令**——在某些状态下会静默失败，进程不启动。  
> **不要直接跑裸二进制**——MenuBarExtra 依赖 bundle 上下文和 Info.plist 的 `LSUIElement=true`。

---

## 已实现功能（2026-05-20 初版，后续持续迭代）

**核心功能**
1. RSS 抓取，11 个内置源，每小时刷新，**只保留当天文章**，过期自动清理
2. AI 单篇摘要：模型生成一句话中文摘要（强制中文，无论原文语言）
3. 今日 AI 资讯摘要：日报整体概述，悬停或点击展开，默认 5 行，max_tokens=300
4. AI 今日推荐：AI 挑选 3 篇，基于标题 + 摘要综合判断，附摘要，不受已读状态影响
5. 推荐区/摘要区**骨架占位**：未生成时显示灰条 + "生成中…" 提示
6. 已读文章显示在列表底部（"已读 (n)" 分隔行），标题色降低；Header 显示 [未读/总数]
7. 订阅源开关：设置页 Toggle，关闭时删除该源文章
8. 去重：启动时自动去重，清理已移除订阅源存量
9. Footer：最后更新精确时间 + 设置 + 退出

**UI 交互**
- 文章行：悬停展开摘要（默认 1 行，悬停显示全文），带 easeInOut 动画
- 推荐区：同上，提取为独立 `RecommendItemView`（需 `.fixedSize(vertical:true)` 才能在 HStack 中正确撑高）
- 摘要区：悬停临时展开 + 点击固定展开，chevron 跟随两个状态变化
- 区域布局：文章列表 → AI 推荐（`.quaternary` 背景）→ 今日摘要（`.quaternary` 背景）
- AI 不可用时 Header 下方显示橙色 Banner，含"去设置"快捷按钮

**设置页**
- RSS 源检测：每行"检测"按钮 + "检测全部"批量检测，行内绿勾/红叉状态图标，底部汇总
- 添加新源时自动验证，失败弹 Alert 允许强制保存
- AI 模型选择：预设 9 个模型（千问 5 / 智谱 2 / Kimi 1 / MiniMax 1）+ 自定义输入
- API 可用性检测：保存时自动检测 + 手动"检测可用性"按钮，行内状态显示

**AI 调用优化**
- 文章摘要：只处理 `aiSummary == nil` 的（原有）
- AI 推荐：有新文章 OR 推荐列表为空时才调用；显示最后更新时间
- 今日日报：`dailyDigest == nil` 时无条件生成；已有内容则需有新文章 AND 距上次 >3h；内容持久化到 UserDefaults，跨重启恢复；显示最后更新时间

---

## 关键文件

| 文件 | 说明 |
|------|------|
| `App/AINewsBarApp.swift` | ModelContainer + SwiftData 迁移失败自动重建 |
| `App/AppDelegate.swift` | 隐藏 Dock 图标 |
| `Services/RefreshService.swift` | 刷新/摘要/推荐调度，@MainActor；含 `AIAvailability` 枚举 |
| `Services/ClaudeService.swift` | DashScope 调用（**类名 BailianService，勿与文件名混淆**）；`recommendArticles` 接收 `summary` 参数 |
| `Services/KeychainService.swift` | **实为 UserDefaults**，名称未改；含模型/日报持久化 |
| `Services/BuiltInFeeds.swift` | 11 个内置源列表 |
| `Views/MenuBarView.swift` | 主界面；两个独立 @Query（未读+已读）；AI 不可用 Banner |
| `Views/ArticleRowView.swift` | 用 `onTapGesture` 而非 `Button`（见踩坑 #1） |
| `Views/SettingsView.swift` | 三 Tab 设置；RSS 行内检测 + CheckStatus 枚举；9 个模型分组 Picker + 自定义输入；API 可用性检测 |
| `Utils/Log.swift` | 日志写到 `~/Downloads/AINewsBar-debug.log` |
| `build/AINewsBar.app` | 打包好的 .app（ad-hoc 签名） |

---

## 内置订阅源（11 个）

OpenAI News, Google DeepMind, Hugging Face Blog, TechCrunch AI, The Verge AI, Ars Technica AI, The Decoder, MIT Tech Review, VentureBeat AI, TLDR AI, 量子位

---

## 踩坑记录

### 1. List 里的 Button 导致行渲染空白

`ArticleRowView` 里**不能用 `Button`**，必须用 `VStack + .contentShape(Rectangle()) + .onTapGesture`。

`MenuBarExtra(.window)` 样式下，`Button + .buttonStyle(.plain)` 放进 `List` 整行渲染空白（SwiftUI bug）。`LazyVStack+ScrollView` 也渲染空白，必须用 `List`。

### 2. SwiftData 新增非可选字段导致迁移崩溃

给 `@Model` 加新的非可选属性后，自动迁移会失败并 fatalError。需在 `AINewsBarApp.swift` 的 catch 块里删除旧数据库并重建。每次改 Model schema 后，先删 `~/Library/Application Support/default.store*` 再运行。

### 3. `open` 命令静默失败

用 `build/AINewsBar.app/Contents/MacOS/AINewsBar &` 直接启动，不用 `open build/AINewsBar.app`。

### 4. 裸二进制运行 MenuBarExtra 图标不显示

必须把二进制放进 .app bundle 再运行，不能直接跑 `.build/debug/AINewsBar`。

### 5. SwiftData @Model 对象不能跨 actor 传递

RSSService 抓完 RSS 后必须返回 `RawArticle: Sendable` 值类型，不能在 actor 里创建 `Article` 对象。跨边界使用会导致静默数据丢失或崩溃。

### 6. @Query 的日期谓词在初始化时捕获，不会自动更新

不能在 `@Query` 的 `#Predicate` 里用 `Date()` 做当天过滤。日期过滤放在 Service 层（RefreshService 插入时过滤 + 刷新时清理旧数据），@Query 只做 isRead 过滤。

### 7. SwiftData 不支持对 Bool 字段排序

`SortDescriptor(\Article.isRead)` 编译报错（`NSObject` 限制）。解决方案：拆成两个独立 `@Query`：一个过滤 `isRead == false`，另一个过滤 `isRead == true`，分别在 List 中 ForEach，中间插入普通行充当分隔符。

### 8. List 的 Section header 带系统背景色

`List` + `.listStyle(.plain)` 下，`Section { } header: { }` 会带 macOS 系统默认的 section header 背景（浅灰/暖色），在浅色外观下明显偏红。解决方案：不用 `Section`，改用普通 `HStack` 行 + `.listRowBackground(Color(nsColor: .separatorColor).opacity(0.12))` 自定义背景。

### 9. 嵌套 HStack 中 Text 高度变化不传导父容器

在 `RecommendItemView` 的 `HStack → VStack → Text` 结构中，`lineLimit` 从 1 变 nil 时文字内容撑高，但父 HStack 不跟随扩展，导致文字被裁剪。修复：在可变高 Text 上加 `.fixedSize(horizontal: false, vertical: true)`，强制父容器按文字自然高度布局。
