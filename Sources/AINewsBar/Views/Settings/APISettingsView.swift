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

    @MainActor
    private func saveAndCheck() async {
        PreferencesService.shared.saveAPIKey(apiKey)
        PreferencesService.shared.saveModel(effectiveModel)
        await checkConnection()
    }

    @MainActor
    private func checkConnection() async {
        guard !apiKey.isEmpty, !effectiveModel.isEmpty else { return }
        checkStatus = .checking
        do {
            try await BailianService.shared.testConnection(apiKey: apiKey, model: effectiveModel)
            checkStatus = .success(1)
            // testConnection 成功是全局信号：清 global error。
            // per-cat aiAvailability 不在此 set —— 旧实现只动 .ai 一个 cat 漏了
            // earnings/news；正确语义是由下次各 cat 自己的 refresh 自然修正。
            refreshService.globalAIError = nil
        } catch {
            checkStatus = .failure(error.localizedDescription)
            // P3-A: 失败时主动 set globalAIError，让菜单主 UI 立即看到状态
            // （而不是等下一轮 refresh）。401/403 映射到 invalidAPIKey/forbidden；
            // 其他错误降级为 .other(localizedDescription)，与 banner UI 复用同套路径。
            refreshService.globalAIError = GlobalAIError.from(error)
                ?? .other(error.localizedDescription)
        }
    }
}
