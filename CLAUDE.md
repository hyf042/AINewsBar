# AINewsBar — Claude 工作记录

## 项目背景

2026-05-15，通过 `/grill-me` 技术访谈完整定义了 AINewsBar 的所有设计决策，随后从零完成代码骨架搭建。

## 设计决策记录

以下决策通过逐问逐答的方式与用户对齐，每个决策均有明确的推荐理由：

| 维度 | 决策 | 理由 |
|------|------|------|
| 应用类型 | macOS 菜单栏应用（Menu Bar App） | RSS 需要后台刷新，WidgetKit 刷新策略不适合 |
| 技术栈 | Swift + SwiftUI + macOS 14+ | 原生体验，MenuBarExtra 成熟，SwiftData 集成顺畅 |
| 数据来源 | 内置精选源 + 用户自定义 RSS | 开箱即用 + 灵活扩展，降低使用门槛 |
| UI 布局 | 混合 Feed 流（时间倒序） | 菜单栏弹窗空间有限，混合流最适合快速浏览 |
| 刷新策略 | 后台每小时 + 打开时按需（超 30 分钟触发） | 兼顾实时性和资源效率 |
| 已读状态 | 本地已读标记 + 菜单栏未读角标 | 非侵入式提示，避免频繁通知打扰 |
| 文章点击 | 浏览器打开原文 + AI 一句话简介 | 符合用户预期，弹窗内嵌 WebView 拥挤 |
| AI 摘要服务 | OpenAI GPT-4o mini | 质量高、价格低（每篇 < $0.001） |
| 摘要触发 | 后台批量生成 + 本地缓存（URL 去重） | 打开即可看到摘要，不重复调用 API |
| 数据持久化 | SwiftData（Feed/Article/AISummary 三张表） | 无历史包袱，@Query 与 SwiftUI 深度集成 |
| 设置界面 | 独立 Settings 窗口（Cmd+,） | 符合 macOS 规范，内容多适合独立窗口 |
| 分发方式 | 仅自用 | 无需公证和 App Store 审核 |
| 开机自启 | 支持，默认关闭（SMAppService） | 尊重用户对登录项的控制权 |
| 通知 | 仅菜单栏角标，无系统通知 | AI 资讯低紧迫性，避免打扰 |

## 代码架构要点

### SwiftData 实体关系
```
Feed (1) ──< Article (1) ──< AISummary (0..1)
```

### 刷新流程
```
App 启动 / 定时器触发
  → RefreshService.refresh()
    → RSSService.fetchArticles(from: feed)  ×N feeds (并发)
    → 过滤已有 URL，插入新 Article
    → 更新未读角标（NotificationCenter）
    → OpenAIService.generateSummary() ×新文章 (串行，避免 rate limit)
    → 缓存 AISummary
```

### 关键文件
- `AINewsBarApp.swift` — `@main`，`MenuBarExtra` + `Settings` scene 定义
- `RefreshService.swift` — 核心调度，`@MainActor ObservableObject`
- `MenuBarView.swift` — 负责 seed 内置 Feed、configure RefreshService
- `KeychainService.swift` — OpenAI Key 安全存储

## 编译状态（2026-05-15）

代码骨架已完成，**尚未编译验证**。

阻塞原因：
- 当前机器 macOS 13.0，未安装 Xcode
- SwiftData 要求 macOS 14+，xcodegen 无法在 macOS 13 安装
- Xcode 需从 App Store 手动安装（约 10GB）

**待用户安装 Xcode 后**：
```bash
open /Users/hyf042/Projects/AINewsBar   # Xcode 自动解析 FeedKit 依赖
# Scheme: AINewsBar, Target: My Mac, Cmd+R
```

预期需要解决的编译问题：
- FeedKit API 细节（`Feed.id`、`Feed.title` 等字段名待验证）
- `@NSApplicationDelegateAdaptor` 与 `MenuBarExtra` 组合兼容性
- SwiftData `#Predicate` 宏的具体语法

## 下一步计划

- [ ] 安装 Xcode，修复编译错误
- [ ] 验证 FeedKit 抓取真实 RSS 数据
- [ ] 测试 OpenAI API 摘要生成
- [ ] 完善 UI 细节（空状态、错误提示、加载动画）
- [ ] 添加文章搜索 / 过滤功能（可选）
