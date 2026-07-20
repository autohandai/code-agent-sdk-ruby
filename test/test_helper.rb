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
