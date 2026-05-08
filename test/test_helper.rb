# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "autohand_sdk"
require "fileutils"
require "minitest/autorun"
require "tmpdir"

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
          puts JSON.generate(jsonrpc: "2.0", id: id, result: { commands: ["model", "permissions"] })
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
