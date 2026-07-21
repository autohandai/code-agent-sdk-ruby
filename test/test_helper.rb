# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "autohand_sdk"
require "fileutils"
require "minitest/autorun"
require "tmpdir"

# rubocop:disable Metrics/ModuleLength -- The inline executable keeps transport tests self-contained.
module FakeCLI
  module_function

  def create
    dir = Dir.mktmpdir("autohand-sdk-fake-cli")
    path = File.join(dir, "autohand")
    File.write(path, script)
    FileUtils.chmod("+x", path)
    [path, dir]
  end

  def script
    <<~RUBY
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      $stdout.sync = true
      $stderr.sync = true

      STDIN.each_line do |line|
        request = JSON.parse(line)
        id = request.fetch("id")
        method = request.fetch("method")
        params = request["params"] || {}
        if (request_log = ENV["AUTOHAND_TEST_REQUEST_LOG"])
          File.open(request_log, "a") { |file| file.puts(JSON.generate(request)) }
        end

        case method
        when "autohand.getState"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              status: "idle",
              sessionId: "session_test",
              model: "test-model",
              workspace: Dir.pwd,
              messageCount: 0
            }
          )
        when "autohand.prompt"
          puts JSON.generate(jsonrpc: "2.0", method: "autohand.turnStart", params: { turnId: "turn_1" })
          puts JSON.generate(jsonrpc: "2.0", method: "autohand.messageUpdate", params: { messageId: "msg_1", delta: "Hello " })
          puts JSON.generate(jsonrpc: "2.0", method: "autohand.messageUpdate", params: { messageId: "msg_1", delta: "Ruby" })
          puts JSON.generate(jsonrpc: "2.0", method: "autohand.messageEnd", params: { messageId: "msg_1", content: "Hello Ruby" })
          puts JSON.generate(jsonrpc: "2.0", method: "autohand.turnEnd", params: { turnId: "turn_1" })
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { content: "Hello Ruby", sessionId: "session_test" })
        when "autohand.permissionResponse"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { received: params })
        when "autohand.permissionAcknowledged"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { success: true })
        when "autohand.directoryAccessResponse"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { success: true })
        when "autohand.directoryAccessAcknowledged"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { success: true })
        when "autohand.changesDecision"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              success: true,
              appliedCount: params.fetch("selectedChangeIds", []).length,
              skippedCount: 1,
              errors: [{ changeId: "change-skipped", error: "conflict" }]
            }
          )
        when "autohand.getHistory"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              sessions: [{
                sessionId: "session-42",
                createdAt: "2026-07-20T00:00:00.000Z",
                lastActiveAt: "2026-07-21T00:00:00.000Z",
                projectName: "tin-wrapper",
                model: "test-model",
                messageCount: 12,
                status: "completed"
              }],
              currentPage: params.fetch("page", 1),
              totalPages: 3,
              totalItems: 25
            }
          )
        when "autohand.getSession"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              success: true,
              sessionId: params.fetch("sessionId"),
              projectName: "tin-wrapper",
              model: "test-model",
              messageCount: 1,
              status: "completed",
              createdAt: "2026-07-20T00:00:00.000Z",
              lastActiveAt: "2026-07-21T00:00:00.000Z",
              summary: "Added SDK support",
              messages: [{
                id: "message-1",
                role: "assistant",
                content: "Done",
                timestamp: "2026-07-21T00:00:00.000Z",
                toolCalls: [{ id: "tool-1", name: "write_file", args: { path: "README.md" } }]
              }],
              workspaceRoot: Dir.pwd
            }
          )
        when "autohand.session.attach"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              success: true,
              sessionId: params.fetch("sessionId"),
              workspaceRoot: Dir.pwd,
              messageCount: 7
            }
          )
        when "autohand.yoloSet", "autohand.yolo.set"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: { success: true, expiresIn: params["timeoutSeconds"] }
          )
        when "autohand.mcp.setVscodeTools"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { success: true })
        when "autohand.mcp.invokeResponse"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { success: true })
        when "autohand.learn.recommend"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              success: true,
              projectSummary: "Nine SDK wrappers",
              audit: [{ skill: "legacy", status: "outdated", reason: "old contract" }],
              recommendations: [{ slug: "rpc-contracts", score: 0.97, reason: "missing typed APIs" }],
              gapAnalysis: params["deep"] ? "Deep contract gap" : nil
            }
          )
        when "autohand.learn.update"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              success: true,
              updated: 1,
              unchanged: 1,
              results: [{ name: "rpc-contracts", status: "updated" }, { name: "ruby", status: "unchanged" }]
            }
          )
        when "autohand.learn.generate"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              success: true,
              skillName: "generated-rpc-contracts",
              skillPath: "/skills/\#{params.fetch("scope")}/generated-rpc-contracts"
            }
          )
        when "autohand.getToolsRegistry"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              tools: [{
                name: "write_file",
                description: "Write a file",
                requiresApproval: true,
                approvalMessage: "Allow file write?",
                source: "builtin",
                schemaVersion: 1,
                reuseHint: "Prefer patches"
              }],
              diagnostics: [{ file: ".autohand/tools/broken.json", reason: "invalid schema" }]
            }
          )
        when "autohand.setContextCompact"
          if ENV["AUTOHAND_TEST_UNKNOWN_EVENT"] == "1"
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.future.event",
              params: { value: 7, nested: { retained: true } }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.error",
              params: { code: 500, message: "sentinel" }
            )
          end
          if ENV["AUTOHAND_TEST_RAW_PARAMS"] == "1"
            [
              ["autohand.hook.preTool", [1, "known-array"]],
              ["autohand.hook.stop", nil],
              ["autohand.hook.notification", "known-scalar"],
              ["autohand.future.array", [2, "future-array"]],
              ["autohand.future.null", nil],
              ["autohand.future.scalar", 42]
            ].each do |notification_method, notification_params|
              puts JSON.generate(
                jsonrpc: "2.0", method: notification_method, params: notification_params
              )
            end
          end
          if ENV["AUTOHAND_TEST_MALFORMED_EVENT"] == "1"
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.automode.iteration",
              params: { sessionId: 7, iteration: "three" }
            )
            [
              ["autohand.hook.preTool", { toolId: "bad" }],
              ["autohand.hook.postTool", { duration: "bad" }],
              ["autohand.hook.fileModified", { changeType: "rename" }],
              ["autohand.hook.prePrompt", { mentionedFiles: [42] }],
              ["autohand.hook.postResponse", { tokensUsageStatus: "estimated" }],
              ["autohand.hook.sessionError", { error: 42 }],
              ["autohand.hook.stop", { tokensUsageStatus: "estimated" }],
              ["autohand.hook.sessionStart", { sessionType: "restart" }],
              ["autohand.hook.sessionEnd", { reason: "timeout" }],
              ["autohand.hook.subagentStop", { success: "yes" }],
              ["autohand.hook.permissionRequest", { args: [] }],
              ["autohand.hook.notification", { message: 42 }],
              ["autohand.hook.contextCompacted", {
                croppedCount: -1, usagePercent: 0.6125, reason: "threshold"
              }],
              ["autohand.hook.contextOverflow", {
                tokensBefore: -1, tokensAfter: 80_000, croppedCount: 6, usagePercent: 1.05
              }],
              ["autohand.hook.contextWarning", { usagePercent: 0.805, remainingTokens: -1 }],
              ["autohand.hook.contextCritical", { usagePercent: -0.01 }]
            ].each do |hook_method, hook_params|
              hook_params[:malformedMarker] = hook_method
              puts JSON.generate(jsonrpc: "2.0", method: hook_method, params: hook_params)
            end
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.error",
              params: { code: 500, message: "sentinel" }
            )
          end
          if ENV["AUTOHAND_TEST_TYPED_EVENTS"] == "1"
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.automode.iteration",
              params: {
                sessionId: "automode-1",
                iteration: 3,
                actions: %w[edit test],
                tokensUsed: 420,
                timestamp: "2026-07-21T01:00:00.000Z"
              }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.automode.complete",
              params: {
                sessionId: "automode-1",
                iterations: 5,
                filesCreated: 2,
                filesModified: 4,
                timestamp: "2026-07-21T01:05:00.000Z"
              }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.automode.error",
              params: {
                sessionId: "automode-2",
                error: "iteration budget exceeded",
                timestamp: "2026-07-21T01:06:00.000Z"
              }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.hook.preTool",
              params: {
                toolId: "tool-7",
                toolName: "write_file",
                args: { path: "README.md" },
                timestamp: "2026-07-21T01:07:00.000Z"
              }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.hook.postTool",
              params: {
                toolId: "tool-7",
                toolName: "write_file",
                success: true,
                duration: 18.5,
                output: "written",
                timestamp: "2026-07-21T01:08:00.000Z"
              }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.hook.prePrompt",
              params: {
                instruction: "Review the SDK",
                mentionedFiles: %w[README.md lib/autohand_sdk.rb],
                timestamp: "2026-07-21T01:09:00.000Z"
              }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.hook.postResponse",
              params: {
                tokensUsed: 1_250,
                tokensUsageStatus: "actual",
                toolCallsCount: 2,
                duration: 415.2,
                timestamp: "2026-07-21T01:10:00.000Z"
              }
            )
            [
              ["autohand.hook.fileModified", {
                filePath: "lib/autohand_sdk.rb", changeType: "modify", toolId: "tool-7",
                timestamp: "2026-07-21T01:10:01.000Z"
              }],
              ["autohand.hook.sessionError", {
                error: "Rate limited", code: "RATE_LIMIT", context: { retryAfter: 60 },
                timestamp: "2026-07-21T01:10:02.000Z"
              }],
              ["autohand.hook.stop", {
                tokensUsed: 700, tokensUsageStatus: "unavailable", toolCallsCount: 3, duration: 300.5,
                timestamp: "2026-07-21T01:10:03.000Z"
              }],
              ["autohand.hook.sessionStart", {
                sessionType: "resume", timestamp: "2026-07-21T01:10:04.000Z"
              }],
              ["autohand.hook.sessionEnd", {
                reason: "clear", duration: 450.5, timestamp: "2026-07-21T01:10:05.000Z"
              }],
              ["autohand.hook.subagentStop", {
                subagentId: "sub-1", subagentName: "reviewer", subagentType: "code-review",
                success: false, duration: 75.5, error: "Review failed",
                timestamp: "2026-07-21T01:10:06.000Z"
              }],
              ["autohand.hook.permissionRequest", {
                tool: "write_file", path: "README.md", command: "write README.md",
                args: { content: "updated" }, timestamp: "2026-07-21T01:10:07.000Z"
              }],
              ["autohand.hook.notification", {
                notificationType: "warning", message: "Context is nearly full",
                timestamp: "2026-07-21T01:10:08.000Z"
              }],
              ["autohand.hook.contextCompacted", {
                croppedCount: 4, summary: "Earlier turns summarized", usagePercent: 0.6125,
                reason: "threshold", timestamp: "2026-07-21T01:10:09.000Z"
              }],
              ["autohand.hook.contextOverflow", {
                tokensBefore: 120_000, tokensAfter: 80_000, croppedCount: 6, usagePercent: 1.05,
                timestamp: "2026-07-21T01:10:10.000Z"
              }],
              ["autohand.hook.contextWarning", {
                usagePercent: 0.805, remainingTokens: 12_000,
                timestamp: "2026-07-21T01:10:11.000Z"
              }],
              ["autohand.hook.contextCritical", {
                usagePercent: 0.9575, remainingTokens: 3_000,
                timestamp: "2026-07-21T01:10:12.000Z"
              }]
            ].each do |hook_method, hook_params|
              puts JSON.generate(jsonrpc: "2.0", method: hook_method, params: hook_params)
            end
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.mcp.invokeRequest",
              params: {
                requestId: "mcp-invoke-9",
                toolName: "open_issue",
                args: { issue: "SDK parity" },
                timestamp: "2026-07-21T01:11:00.000Z"
              }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.mcp.toolsChanged",
              params: {
                tools: [{ name: "open_issue", description: "Open an issue", serverName: "vscode" }],
                timestamp: "2026-07-21T01:12:00.000Z"
              }
            )
            puts JSON.generate(
              jsonrpc: "2.0",
              method: "autohand.learn.progress",
              params: {
                status: "evaluating",
                timestamp: "2026-07-21T01:13:00.000Z"
              }
            )
          end
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { enabled: params.fetch("enabled") })
        when "autohand.planModeSet"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { enabled: params["enabled"] })
        when "autohand.modelSet"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { model: params["model"] })
        when "autohand.getSupportedModels"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { models: [{ id: "test-model" }] })
        when "autohand.getSupportedCommands"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { commands: ["model", "/permissions", "autoresearch"] })
        when "autohand.getSkillsRegistry"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              success: true,
              skills: [{
                id: "typescript",
                name: "TypeScript",
                description: "Typed JavaScript",
                category: "language",
                downloadCount: 42,
                isCurated: true
              }],
              categories: [{ name: "language", count: 1 }]
            }
          )
        when "autohand.installSkill"
          success = params["skillName"] != "existing"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: success ? {
              success: true,
              skillName: params["skillName"],
              path: "/skills/\#{params["scope"]}/\#{params["skillName"]}"
            } : { success: false, error: "already installed" }
          )
        when "autohand.mcp.listServers"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: { servers: [{ name: "github", status: "connected", toolCount: 3 }] }
          )
        when "autohand.mcp.listTools"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: { tools: [{ name: "issues", description: "List issues", serverName: params["serverName"] || "github" }] }
          )
        when "autohand.mcp.getServerConfigs"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              configs: [{
                name: "github",
                transport: "http",
                url: "https://example.test/mcp",
                headers: { Authorization: "test" },
                autoConnect: true
              }]
            }
          )
        when "autohand.argv"
          puts JSON.generate(jsonrpc: "2.0", id: id, result: ARGV)
        when "autohand.autoresearch.status"
          puts JSON.generate(
            jsonrpc: "2.0",
            method: "autohand.autoresearch.status",
            params: {
              active: true,
              goal: "Reduce test runtime",
              iteration: 3,
              maxIterations: 12,
              runsLogged: 3,
              statusText: "Auto-research active",
              subcommand: "status",
              timestamp: "2026-07-17T00:00:00.000Z"
            }
          )
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { success: true, active: true, runsLogged: 3 })
        when "autohand.autoresearch.replay"
          puts JSON.generate(
            jsonrpc: "2.0",
            method: "autohand.autoresearch.event",
            params: {
              operation: "replay",
              phase: "complete",
              success: true,
              attemptId: params["attemptId"],
              timestamp: "2026-07-17T00:00:00.000Z"
            }
          )
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: { success: true, attemptId: params["attemptId"], method: method, params: params }
          )
        when "autohand.env"
          puts JSON.generate(
            jsonrpc: "2.0",
            id: id,
            result: {
              "BUNDLE_GEMFILE" => ENV["BUNDLE_GEMFILE"],
              "RUBYOPT" => ENV["RUBYOPT"],
              "RUBYLIB" => ENV["RUBYLIB"],
              "GEM_HOME" => ENV["GEM_HOME"],
              "GEM_PATH" => ENV["GEM_PATH"]
            }
          )
        else
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { ok: true, method: method, params: params })
        end
      end
    RUBY
  end
end
# rubocop:enable Metrics/ModuleLength

class SDKTestCase < Minitest::Test
  def setup
    AutohandSDK.reset_configuration!
    @cli_path, @cli_dir = FakeCLI.create
  end

  def teardown
    FileUtils.remove_entry(@cli_dir) if @cli_dir && Dir.exist?(@cli_dir)
    AutohandSDK.reset_configuration!
  end

  def client(**)
    AutohandSDK::Client.new(cli_path: @cli_path, startup_check: true, timeout: 2_000, **)
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
