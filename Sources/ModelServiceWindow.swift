import Cocoa

extension AssistantApp {
    func modelResponse(messages: [[String: Any]], maxTokens: Int = 9000, jsonOutput: Bool = false, using selected: ModelService? = nil) async throws -> String {
        let chosen = selected ?? service, selectedModel = model
        if chosen == .chatGPT {
            return try await CodexClient().complete(messages: messages, maxTokens: maxTokens, jsonOutput: jsonOutput)
        }
        let saved = try await Task.detached(priority: .userInitiated) { try KeyStore.read() }.value
        try Task.checkCancellation()
        guard let key = saved, !key.isEmpty else { throw AssistantFailure(message: "请先在模型设置中连接 DeepSeek API，或选择 ChatGPT 订阅。") }
        return try await DeepSeekClient().reading(messages: messages, key: key, model: selectedModel, maxTokens: maxTokens, jsonOutput: jsonOutput)
    }
    func saveSubscription() {
        saveButton.isEnabled = false; servicePicker.isEnabled = false
        settingsStatus.stringValue = "正在检查本机 Codex 登录状态…"
        validationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await CodexClient().checkLogin(); try Task.checkCancellation()
                UserDefaults.standard.set(ModelService.chatGPT.rawValue, forKey: "modelService")
                self.refreshServiceUI()
                self.settingsStatus.stringValue = "已启用 ChatGPT 订阅。检查登录未发起模型请求；写作、导读和问答均使用此服务。"
                self.status("已切换到 ChatGPT 订阅（经 Codex）。")
            } catch { self.settingsStatus.stringValue = error.localizedDescription }
            self.saveButton.isEnabled = true; self.servicePicker.isEnabled = true; self.validationTask = nil
        }
    }
    func refreshServiceUI() {
        window?.title = "学术助手 · \(service.title)"
        if let reader {
            reader.window.title = "论文阅读 · \(service.title)"
            reader.visionToggle.isEnabled = service == .deepseek && !reader.busy
            if service == .chatGPT { reader.visionToggle.state = .off }
            reader.visionToggle.title = service == .chatGPT ? "图表（订阅仅文字）" : "图表"
            reader.askButton.title = service == .chatGPT ? "订阅回答" : "DeepSeek 回答"
            reader.generateButton.toolTip = "使用 \(service.title) 生成中文导读"
        }
        if let indexWindow {
            indexWindow.window.title = "论文索引 · \(service.title)"
            if indexWindow.memoryTask == nil { indexWindow.askButton.title = service.answerTitle }
        }
    }
}
