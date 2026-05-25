import SwiftUI

struct APISettingsView: View {
    @State private var apiKey = ""
    @State private var isRevealed = false
    @State private var selectedModel = PreferencesService.defaultModel
    @State private var useCustomModel = false
    @State private var customModel = ""
    @State private var checkStatus: CheckStatus = .idle
    @EnvironmentObject private var refreshService: RefreshService

    private static let modelGroups: [(brand: String, models: [String])] = [
        ("千问", ["qwen3.6-plus", "qwen3.5-plus", "qwen3-max-2026-01-23", "qwen3-coder-next", "qwen3-coder-plus"]),
        ("智谱", ["glm-5", "glm-4.7"]),
        ("Kimi", ["kimi-k2.5"]),
        ("MiniMax", ["MiniMax-M2.5"])
    ]

    private var effectiveModel: String {
        useCustomModel ? customModel : selectedModel
    }

    private var isChecking: Bool {
        if case .checking = checkStatus { return true }
        return false
    }

    var body: some View {
        Form {
            Section("阿里云百炼 API Key") {
                HStack {
                    if isRevealed {
                        TextField("sk-...", text: $apiKey)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                    }
                    Button { isRevealed.toggle() } label: {
                        Text(isRevealed ? "隐藏" : "显示")
                            .foregroundStyle(BrandColor.accent)
                    }
                    .buttonStyle(.plain)
                }
                Text("前往 bailian.console.aliyun.com 获取")
                    .font(Typography.caption).foregroundStyle(TextColor.secondary)
            }

            Section("模型") {
                if !useCustomModel {
                    Picker("选择模型", selection: $selectedModel) {
                        ForEach(Self.modelGroups, id: \.brand) { group in
                            Section(group.brand) {
                                ForEach(group.models, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                } else {
                    LabeledContent("自定义模型") {
                        TextField("输入模型名称", text: $customModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                Toggle("使用自定义模型", isOn: $useCustomModel)
                    .onChange(of: useCustomModel) { _, _ in checkStatus = .idle }
            }

            Section {
                checkStatusRow
                HStack {
                    Button("检测可用性") { Task { await checkConnection() } }
                        .tint(BrandColor.accent)
                        .disabled(apiKey.isEmpty || effectiveModel.isEmpty || isChecking)
                    Spacer()
                    Button("保存") { Task { await saveAndCheck() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    @ViewBuilder
    private var checkStatusRow: some View {
        switch checkStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                Text("检测中…").font(Typography.caption).foregroundStyle(TextColor.secondary)
            }
        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(Typography.caption)
                Text("API Key 和模型均可用").font(Typography.caption).foregroundStyle(TextColor.secondary)
            }
        case .failure(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(Typography.caption)
                Text(msg).font(Typography.caption).foregroundStyle(TextColor.secondary).lineLimit(2)
            }
        }
    }

    private func loadSettings() {
        apiKey = PreferencesService.shared.getAPIKey() ?? ""
        let saved = PreferencesService.shared.getModel()
        let allModels = Self.modelGroups.flatMap(\.models)
        if allModels.contains(saved) {
            selectedModel = saved
            useCustomModel = false
        } else {
            customModel = saved
            useCustomModel = true
        }
    }

    /// P2 第六轮 review：**先验证候选值，成功后才持久化**。
    /// 旧路径先 saveAPIKey/saveModel 再 testConnection —— 用户手滑输错就把上一套
    /// 可用配置覆盖了，主流程从下次 refresh 起也用坏配置。
    /// 新路径：失败时 prefs 完全不动，主 UI 仍用旧 key（可能可用）继续工作。
    @MainActor
    private func saveAndCheck() async {
        guard !apiKey.isEmpty, !effectiveModel.isEmpty else { return }
        checkStatus = .checking
        do {
            try await BailianService.shared.testConnection(apiKey: apiKey, model: effectiveModel)
            // 验证通过 → 持久化
            PreferencesService.shared.saveAPIKey(apiKey)
            PreferencesService.shared.saveModel(effectiveModel)
            checkStatus = .success(1)
            // 触发 onboarding 路径：清 credential 错误 + 顺序刷新三 cat
            let service = refreshService
            Task { await service.applyCredentialChange() }
        } catch {
            // 验证失败 → 不动 prefs（保留上一套可用配置）
            checkStatus = .failure(error.localizedDescription)
            // 主动 set globalAIError 让主 UI 看到"当前输入这组 credential 不可用"；
            // 若旧 key 可用，下次 refresh 的 clearGlobalAIErrorAfterAISuccess 会清掉
            refreshService.globalAIError = GlobalAIError.from(error)
                ?? .other(error.localizedDescription)
        }
    }

    @MainActor
    private func checkConnection() async {
        guard !apiKey.isEmpty, !effectiveModel.isEmpty else { return }
        checkStatus = .checking
        do {
            try await BailianService.shared.testConnection(apiKey: apiKey, model: effectiveModel)
            checkStatus = .success(1)
            // 仅测试通过，不持久化（按钮语义是"检测可用性"）
            // testConnection 成功是全局信号：清 global error。per-cat aiAvailability
            // 不在此 set —— 由下次各 cat 自己的 refresh 自然修正。
            refreshService.globalAIError = nil
        } catch {
            checkStatus = .failure(error.localizedDescription)
            refreshService.globalAIError = GlobalAIError.from(error)
                ?? .other(error.localizedDescription)
        }
    }
}
