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
| UI 布局 | 混合 Feed 流（时间倒序） | 菜单栏弹窗空间有限，混合流最适合快速浏览 |
| 刷新策略 | 后台每小时 + 打开时按需（超 30 分钟触发） | 兼顾实时性和资源效率 |
| 已读状态 | 本地标记 + @Query 过滤（isRead==false） | 非侵入式，点击后消失 |
| 文章点击 | 浏览器打开原文 + AI 一句话简介 | 符合用户预期 |
| AI 摘要服务 | 阿里云百炼 DashScope，模型 qwen-plus | 原设计 OpenAI，改为 DashScope 避免 Keychain ad-hoc 签名弹窗 |
| 密钥存储 | UserDefaults（key: `com.ainewsbar.claude-api-key`） | 原设计 Keychain，ad-hoc 签名每次弹授权窗口，改为 UserDefaults |
| 数据持久化 | SwiftData（Feed / Article 两张表） | @Query 与 SwiftUI 深度集成；AISummary 已合并到 Article 字段 |
| 分发方式 | 仅自用，ad-hoc 签名 | 无需公证和 App Store 审核 |

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

## 已实现功能（2026-05-20 全部完成）

1. RSS 抓取，11 个内置源，每小时刷新，**只保留当天文章**，过期自动清理
2. AI 单篇摘要：qwen-plus 生成一句话中文摘要（强制中文，无论原文语言）
3. 今日 AI 资讯摘要：日报整体概述，可展开/收起，默认 5 行，max_tokens=300
4. AI 今日推荐：每次刷新 AI 挑选 3 篇，附摘要，不受已读状态影响
5. 摘要/推荐区**骨架占位**：未生成时显示灰条 + "生成中…" 提示
6. 已读过滤：@Query 只显示 isRead==false，点击后消失
7. 订阅源开关：设置页 Toggle，关闭时删除该源文章
8. 去重：启动时自动去重，清理已移除订阅源存量
9. Footer：最后更新精确时间 + 设置 + 退出

---

## 关键文件

| 文件 | 说明 |
|------|------|
| `App/AINewsBarApp.swift` | ModelContainer + SwiftData 迁移失败自动重建 |
| `App/AppDelegate.swift` | 隐藏 Dock 图标 |
| `Services/RefreshService.swift` | 刷新/摘要/推荐调度，@MainActor |
| `Services/ClaudeService.swift` | DashScope 调用（**类名 BailianService，勿与文件名混淆**） |
| `Services/KeychainService.swift` | **实为 UserDefaults**，名称未改 |
| `Services/BuiltInFeeds.swift` | 11 个内置源列表 |
| `Views/MenuBarView.swift` | 主界面，含摘要区/推荐区 |
| `Views/ArticleRowView.swift` | 用 `onTapGesture` 而非 `Button`（见踩坑 #1） |
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
