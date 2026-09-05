# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "socket"
require "io/wait"
require "timeout"

class HarnessStepControlTest < Minitest::Test
  class ProviderMock
    attr_reader :url

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @url = "http://127.0.0.1:#{@server.addr[1]}"
      @calls = []
      @mutex = Mutex.new
      @stopped = false
      @worker = Thread.new do
        until @stopped
          next unless @server.wait_readable(0.1)

          serve(@server.accept)
        end
      end
    end

    def calls
      @mutex.synchronize { @calls.dup }
    end

    def close
      @stopped = true
      @worker.join(6) || @worker.kill.join
      @worker.value
    ensure
      @server.close
    end

    private

    def serve(socket)
      Timeout.timeout(5) do
        path = socket.gets.split[1]
        headers = {}
        while (line = socket.gets) && line != "\r\n"
          key, value = line.split(":", 2)
          headers[key.downcase] = value.strip
        end
        body = socket.read(headers.fetch("content-length", "0").to_i)
        response = JSON.generate(response_for(path, headers, body))
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                     "Content-Length: #{response.bytesize}\r\nConnection: close\r\n\r\n#{response}")
      end
    ensure
      socket.close
    end

    def response_for(path, headers, body)
      if path == "/auth/me"
        return { authenticated: true, user: { id: "fixture", email: "sdk@example.test", name: "SDK Fixture" } }
      end
      raise "Unexpected provider path: #{path}" unless path == "/chat/completions"
      raise "Missing mock credential" unless headers["authorization"] == "Bearer sdk-fixture-key"

      count = @mutex.synchronize do
        @calls << JSON.parse(body)
        @calls.length
      end
      message = if count == 1
                  { role: "assistant", content: "Inspect the evidence file.", tool_calls: [
                    { id: "call-read", type: "function",
                      function: { name: "read_file", arguments: JSON.generate(path: "evidence.txt") } }
                  ] }
                else
                  { role: "assistant", content: "continued from persisted evidence" }
                end
      { id: "fixture", choices: [{ message: message, finish_reason: "stop" }],
        usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 } }
    end
  end

  def test_current_harness_persists_tool_results_across_stop_and_resume
    cli = ENV.fetch("AUTOHAND_TEST_CLI_PATH", nil)
    skip "Set AUTOHAND_TEST_CLI_PATH to exercise the actual CLI with local HTTP mocks" unless cli

    verify_harness(cli)
  end

  private

  def verify_harness(cli)
    provider = ProviderMock.new
    Dir.mktmpdir("ruby-sdk-harness") do |workspace|
      File.write(File.join(workspace, "evidence.txt"), "sdk-parity-evidence")
      config = File.join(workspace, "config.json")
      File.write(config, JSON.generate(
                           auth: { token: "sdk-fixture-key" }, provider: "autohandai",
                           autohandai: { model: "fantail", plan: "cloud", authMode: "api-key", contextWindow: 200_000 },
                           features: { autohand_inference: true, automaticSpecialists: false },
                           telemetry: { enabled: false }
                         ))
      AutohandSDK::Agent.open(
        cli_path: cli, cwd: workspace, timeout: 45_000, bare: true, unrestricted: true,
        provider: "autohandai", model: "fantail", api_key: "sdk-fixture-key", base_url: provider.url,
        extra_args: ["--config", config], env_vars: {
          "AUTOHAND_HOME" => File.join(workspace, "home"),
          "AUTOHAND_API_KEY" => "sdk-fixture-key", "AUTOHAND_API_URL" => provider.url,
          "AUTOHAND_AUTH_API_URL" => "#{provider.url}/auth", "AUTOHAND_SKIP_PING" => "1",
          "AUTOHAND_SKIP_UPDATE_CHECK" => "1", "AUTOHAND_NO_IDLE_LOGOUT" => "1",
          "AUTOHAND_DISABLE_AUTO_REPORT" => "1"
        }
      ) do |agent|
        result = Timeout.timeout(45) do
          agent.run("Read evidence.txt with read_file.", stop_when: AutohandSDK.is_step_count(1))
        end

        assert_equal("stopped", result.fetch(:status))
        assert_equal(1, result.fetch(:steps).length)
        assert_equal(1, provider.calls.length)
        tool_result = result.fetch(:steps).first.tool_results.first

        assert(tool_result.success)
        assert_includes(tool_result.output, "sdk-parity-evidence")

        continued = Timeout.timeout(45) { agent.run("Continue using the saved tool result.") }

        assert_equal("completed", continued.fetch(:status))
        assert_equal(2, provider.calls.length)
        assert_includes(JSON.generate(provider.calls.last.fetch("messages")), "sdk-parity-evidence")
      end
    end
  ensure
    provider&.close
  end
end
