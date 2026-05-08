# frozen_string_literal: true

require_relative "test_helper"

class TransportTest < SDKTestCase
  def test_request_returns_rpc_result
    transport = AutohandSDK::Transport.new(cli_path: @cli_path, cwd: Dir.pwd, timeout: 2_000)
    transport.start

    state = transport.request("autohand.getState")

    assert_equal("idle", state.fetch("status"))
    assert_equal("test-model", state.fetch("model"))
  ensure
    transport&.stop
  end

  def test_notification_subscription_receives_events
    transport = AutohandSDK::Transport.new(cli_path: @cli_path, cwd: Dir.pwd, timeout: 2_000)
    notifications = Queue.new
    transport.on_notification("autohand.messageEnd") { |params| notifications << params }
    transport.start

    transport.request("autohand.prompt", "message" => "hello")

    notification = notifications.pop

    assert_equal("Hello Ruby", notification.fetch("content"))
    assert_equal("autohand.messageEnd", notification.fetch("_method"))
  ensure
    transport&.stop
  end

  def test_subprocess_environment_scrubs_bundler_and_ruby_runtime_variables
    with_env(
      "BUNDLE_GEMFILE" => "/tmp/should-not-leak",
      "RUBYOPT" => "-rbundler/setup",
      "RUBYLIB" => "/tmp/should-not-leak",
      "GEM_HOME" => "/tmp/should-not-leak",
      "GEM_PATH" => "/tmp/should-not-leak"
    ) do
      transport = AutohandSDK::Transport.new(cli_path: @cli_path, cwd: Dir.pwd, timeout: 2_000)
      transport.start

      env = transport.request("autohand.env")

      assert_nil(env.fetch("BUNDLE_GEMFILE"))
      assert_nil(env.fetch("RUBYOPT"))
      assert_nil(env.fetch("RUBYLIB"))
      assert_nil(env.fetch("GEM_HOME"))
      assert_nil(env.fetch("GEM_PATH"))
    ensure
      transport&.stop
    end
  end
end
