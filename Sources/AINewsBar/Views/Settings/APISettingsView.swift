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

    /// 第十二轮 P3：输入边界统一 trim。用户从网页/聊天复制 key 常带尾部空白/换行，
    /// 旧实现 testConnection 用原值会莫名 HTTP 401（DashScope 拒绝 `Authorization: Bearer sk-...\n`），
    /// 保存路径也把原值写进 UserDefaults 污染主流程。所有 caller 走这两个 computed property。
    /// selectedModel 来自 Picker 固定值不必 trim，但 effectiveModel 仍走 trim 保统一语义。
    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedCustomModel: String {
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var effectiveModel: String {
        let raw = useCustomModel ? trimmedCustomModel : selectedModel
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        .disabled(trimmedAPIKey.isEmpty || effectiveModel.isEmpty || isChecking)
                    Spacer()
                    Button("保存") { Task { await saveAndCheck() } }
                        .buttonStyle(.borderedProminent)
                        // 与"检测可用性"对齐：saveAndCheck() 内 guard 要求 effectiveModel 非空，
                        // 旧条件只判 key 让自定义模型为空时按钮可点却静默无事；isChecking 防检测中并发再触发。
                        .disabled(trimmedAPIKey.isEmpty || effectiveModel.isEmpty || isChecking)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
        // 第十二轮 P3：输入变化即重置 checkStatus，避免"检测成功后改了输入仍显示已可用"误导。
        // useCustomModel 已在 Section 内有 onChange；这里补齐另三个输入源。
        .onChange(of: apiKey) { _, _ in checkStatus = .idle }
        .onChange(of: customModel) { _, _ in checkStatus = .idle }
        .onChange(of: selectedModel) { _, _ in checkStatus = .idle }
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

    /// 第六轮 P2 + 第八轮 P3：**先验证候选值，成功后才持久化**；失败完全不动主 UI 状态。
    ///
    /// 旧路径先 saveAPIKey/saveModel 再 testConnection —— 用户手滑输错就把上一套
    /// 可用配置覆盖了。第六轮改为"验后保存"，但失败仍设 globalAIError 污染主 UI。
    /// 第八轮：失败时 prefs 未变，主 UI 反映的是"当前持久化配置"的状态，不该被
    /// 一个未保存的候选输入污染。失败只更新本页 checkStatus，与 checkConnection 对齐。
    @MainActor
    private func saveAndCheck() async {
        // 第十二轮 P3：所有 caller 走 trimmed 值，避免空白进 testConnection / prefs。
        let key = trimmedAPIKey
        let model = effectiveModel
        guard !key.isEmpty, !model.isEmpty else { return }
        checkStatus = .checking
        do {
            try await BailianService.shared.testConnection(apiKey: key, model: model)
            // 验证通过 → 持久化 + 触发主流程
            PreferencesService.shared.saveAPIKey(key)
            PreferencesService.shared.saveModel(model)
            checkStatus = .success(1)
            // onboarding 路径：清 credential 错误 + 顺序刷新三 cat
            let service = refreshService
            Task { await service.applyCredentialChange() }
        } catch {
            // 验证失败 → 不动 prefs，也不动 globalAIError
            // 候选值与主流程持久化值是两份数据，状态隔离
            checkStatus = .failure(error.localizedDescription)
        }
    }

    /// "检测可用性" 按钮：纯查询语义 —— 测候选 key/model 能不能跑通，**完全不动**
    /// refreshService.globalAIError。
    ///
    /// 第七轮 P3 review：旧实现成功清/失败设 globalAIError，会污染主 UI 状态：
    /// - 旧 prefs 中 key 已坏（主 UI 显示 globalAIError），用户拿候选好 key 来测 → 误清主 UI 错误
    /// - 旧 prefs 中 key 好，用户拿候选坏 key 来测 → 误显示全局错误，主 UI 误报
    /// 检测按钮的"输入"和主流程的"持久化值"是两份数据，状态必须隔离。
    /// 主 UI 状态只能由实际运行中的 refresh / saveAndCheck 持久化路径来改。
    @MainActor
    private func checkConnection() async {
        let key = trimmedAPIKey
        let model = effectiveModel
        guard !key.isEmpty, !model.isEmpty else { return }
        checkStatus = .checking
        do {
            try await BailianService.shared.testConnection(apiKey: key, model: model)
            checkStatus = .success(1)
        } catch {
            checkStatus = .failure(error.localizedDescription)
        }
    }
}
