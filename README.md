# AINewsBar

macOS 菜单栏 AI 资讯阅读器，每日自动抓取最新 AI 资讯，支持 RSS 订阅，并通过 OpenAI GPT-4o mini 生成一句话摘要。

## 功能

- **菜单栏常驻**：点击图标展开文章列表，不干扰工作流
- **内置精选源**：预置 6 个高质量 AI 资讯 RSS 源（OpenAI、Anthropic、DeepMind 等）
- **自定义 RSS**：支持添加任意 RSS / Atom / JSON Feed
- **AI 摘要**：后台自动调用 GPT-4o mini 为每篇文章生成一句话简介
- **已读追踪**：本地记录已读状态，菜单栏图标显示未读角标
- **智能刷新**：每小时自动后台刷新，打开弹窗时如超过 30 分钟也自动触发
- **开机自启**：可选，默认关闭

## 技术栈

| 模块 | 技术 |
|------|------|
| UI | Swift + SwiftUI（MenuBarExtra） |
| 数据持久化 | SwiftData |
| RSS 解析 | [FeedKit](https://github.com/nmdias/FeedKit) |
| AI 摘要 | OpenAI GPT-4o mini API |
| 密钥存储 | macOS Keychain |
| 开机自启 | SMAppService |

**最低系统要求：macOS 14 Sonoma**

## 项目结构

```
Sources/AINewsBar/
├── App/
│   ├── AINewsBarApp.swift       # @main，定义 MenuBarExtra + Settings scene
│   └── AppDelegate.swift        # 隐藏 Dock 图标，仅菜单栏运行
├── Models/
│   ├── Feed.swift               # SwiftData 模型：RSS 订阅源
│   ├── Article.swift            # SwiftData 模型：文章
│   └── AISummary.swift          # SwiftData 模型：AI 摘要缓存
├── Services/
│   ├── BuiltInFeeds.swift       # 内置 6 个 AI 资讯源
│   ├── RSSService.swift         # FeedKit 封装，支持 RSS/Atom/JSON Feed
│   ├── OpenAIService.swift      # GPT-4o mini 摘要生成
│   ├── RefreshService.swift     # 定时 + 按需刷新调度
│   └── KeychainService.swift    # API Key 安全读写
└── Views/
    ├── MenuBarView.swift         # 弹窗主界面（文章 Feed 流）
    ├── ArticleRowView.swift      # 文章行视图（含 AI 摘要）
    └── SettingsView.swift        # 设置窗口（订阅/API Key/通用）
```

## 快速开始

### 1. 环境要求

- macOS 14 Sonoma 或更高
- Xcode 15 或更高

### 2. 打开项目

```bash
open /Users/hyf042/Projects/AINewsBar
```

Xcode 会自动识别 `Package.swift` 并解析 FeedKit 依赖（需要联网）。

### 3. 运行

1. Scheme 选择 `AINewsBar`
2. 目标选择 `My Mac`
3. `Cmd+R` 运行

### 4. 配置 OpenAI API Key

启动后点击菜单栏图标 → **设置（Cmd+,）** → **API** → 填入 API Key → 保存

Key 安全存储在 macOS Keychain 中，不写入任何文件。

## 内置订阅源

| 名称 | URL |
|------|-----|
| OpenAI Blog | https://openai.com/blog/rss.xml |
| Anthropic News | https://www.anthropic.com/rss.xml |
| Google DeepMind | https://deepmind.google/blog/rss.xml |
| The Batch (DeepLearning.AI) | https://www.deeplearning.ai/the-batch/feed/ |
| 机器之心 | https://www.jiqizhixin.com/rss |
| 36Kr AI | https://36kr.com/feed |

## 设计决策

本项目通过 `/grill-me` 技术访谈得出所有关键设计决策，详见 `CLAUDE.md`。
