import Foundation

@main struct CodexTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); print("PASS: \(message)")
    }
    static func output(_ lines: [String], status: Int32 = 0, stderr: String = "") -> LocalProcessOutput {
        LocalProcessOutput(status: status, stdout: Data(lines.joined(separator: "\n").utf8), stderr: Data(stderr.utf8))
    }
    static let answer = #"{"type":"item.completed","item":{"type":"agent_message","text":"{\"text\":\"READY\"}"}}"#
    static let completed = #"{"type":"turn.completed"}"#
    static func rejects(_ lines: [String], status: Int32 = 0) -> Bool {
        do { _ = try CodexClient.decode(output(lines, status: status)); return false } catch { return true }
    }
    static func main() async throws {
        let env = CodexClient.environment(["HOME":"/tmp/test", "OPENAI_API_KEY":"test", "CODEX_API_KEY":"test", "OPENAI_BASE_URL":"https://invalid", "CODEX_HOME":"/tmp/wrong", "CODEX_THREAD_ID":"parent"])
        check(env["HOME"] == "/tmp/test" && env.count == 2, "Child environment excludes API credentials, endpoints and parent identity")
        check(CodexClient.isSubscription(output([], stderr: "Logged in using ChatGPT")), "Official ChatGPT login is accepted")
        check(!CodexClient.isSubscription(output([], stderr: "Logged in using an API key")), "API-key login is rejected")
        check(!CodexClient.isSubscription(output([], status: 1, stderr: "Logged in using ChatGPT")), "Failed status cannot authorize subscription use")
        let decoded = try CodexClient.decode(output([answer, completed]))
        check(decoded == "READY", "Completed structured result is decoded")
        let warning = #"{"type":"item.completed","item":{"type":"error","message":"Code Mode is unavailable because code-mode host is disabled. Code mode will fail closed."}}"#
        let warnedReply = try CodexClient.decode(output([warning, answer, completed]))
        check(warnedReply == "READY", "Known disabled-tool warning does not hide a completed answer")
        check(rejects([answer]), "Partial answers are rejected")
        check(rejects([answer, completed], status: 1), "Failed process cannot return an answer")
        check(rejects([answer, #"{"type":"turn.failed"}"#]), "Failed turns are rejected")
        check(rejects([#"{"type":"item.completed","item":{"type":"agent_message","text":"plain text"}}"#, completed]), "Unstructured output is rejected")
        check(rejects([#"{"type":"item.completed","item":{"type":"command_execution"}}"#, answer, completed]), "Unexpected tool execution cannot be accepted")
        check(rejects([#"{"type":"item.completed","item":{"type":"error","message":"unknown failure"}}"#, answer, completed]), "Unknown error items fail closed")
        do { _ = try CodexClient.decode(output([#"{"type":"error","message":"usage_limit"}"#])); fatalError("quota accepted") }
        catch { check(error.localizedDescription.contains("未切换到付费 API"), "Quota failures explicitly state no API fallback") }
        let prompt = try CodexClient.prompt(messages: [["role":"user", "content":[["type":"text", "text":"保留 \\cite{test} 与 $x^2$"]]]], outputLimit: 80, jsonOutput: true)
        check(prompt.contains("$x^2$") && prompt.contains("JSON 对象"), "Text blocks and task format survive prompt preparation")
        let unsupported: [Any] = [[ ["type":"image_url", "image_url":["url":"data:test"]] ], String(repeating:"文", count:160_001)]
        for content in unsupported {
            do { _ = try CodexClient.prompt(messages:[["content":content]], outputLimit:80, jsonOutput:false); fatalError("unsupported input accepted") }
            catch { check(true, "Unsupported or oversized content is rejected before inference") }
        }
        do { _ = try CodexClient.prompt(messages:Array(repeating:["content":"a"], count:41), outputLimit:80, jsonOutput:false); fatalError("unbounded history") }
        catch { check(true, "Conversation count is bounded") }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("subscription-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory, withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:directory) }
        let script = directory.appendingPathComponent("fake-codex")
        func fixture(_ text: String) throws {
            try Data(("#!/bin/sh\n" + text).utf8).write(to:script)
            try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath:script.path)
        }
        try fixture("""
        if [ "$1" = login ]; then echo 'Logged in using ChatGPT' >&2; exit 0; fi
        cat >/dev/null
        echo '\(answer)'
        echo '\(completed)'
        """)
        let client = CodexClient(executableOverride:script, processTimeout:3)
        let reply = try await client.complete(messages:[["role":"user","content":String(repeating:"x", count:100_000)]], maxTokens:80)
        check(reply == "READY", "Full client handles large stdin without pipe deadlock")
        try fixture("if [ \"$1\" = login ]; then echo 'Logged in using an API key'; exit 0; fi\nexit 99\n")
        do { _ = try await client.complete(messages:[["content":"test"]], maxTokens:80); fatalError("API account used") }
        catch { check(error.localizedDescription.contains("订阅登录"), "Client rejects API account before running inference") }
        try fixture("exec /bin/sleep 30\n")
        do { _ = try await LocalProcessJob().run(executable:script, arguments:[], environment:env, directory:directory, input:Data(), timeout:0.1); fatalError("timeout ignored") }
        catch { check(error.localizedDescription.contains("超时"), "Timeout stops the client and reports no fallback") }
        let job = Task { try await LocalProcessJob().run(executable:script, arguments:[], environment:env, directory:directory, input:Data(), timeout:5) }
        try await Task.sleep(nanoseconds:100_000_000); job.cancel()
        do { _ = try await job.value; fatalError("cancel ignored") }
        catch { check(error is CancellationError, "Cancellation stops the child process") }
    }
}
