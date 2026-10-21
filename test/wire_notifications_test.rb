# frozen_string_literal: true

require_relative "test_helper"

class WireNotificationsTest < Minitest::Test
  def test_ephemeral_mode_is_explicit
    refute_includes AutohandSDK::Transport.new.send(:build_args), "--ephemeral"
    assert_includes AutohandSDK::Transport.new(ephemeral: true).send(:build_args), "--ephemeral"
  end

  def test_rejects_obsolete_options_before_launching
    transport = AutohandSDK::Transport.new(cli_path: "/does-not-exist", auto_save_interval: 30)
    error = assert_raises(AutohandSDK::ConfigurationError) { transport.start }

    assert_includes error.message, "unsupported by the current CLI"
  end

  def test_preserves_packets_handlers_and_independent_observers
    transport = AutohandSDK::Transport.new
    rpc = AutohandSDK::RPCClient.new(nil, transport: transport)
    agent = AutohandSDK::Agent.new(AutohandSDK::Client.new(nil, rpc_client: rpc))
    packets = []
    typed = []
    transport.on_notification("autohand.pipe.output") { |packet| typed << packet }
    agent.on_notification { raise "observer failure" }
    agent.on_notification { |packet| packet.params << "mutated" if packet.params.is_a?(Array) }
    remove = agent.on_notification { |packet| packets << packet }
    payloads = [{ "type" => "progress", "future" => false }, [1, nil, false], nil]
    payloads.each do |payload|
      transport.send(:handle_rpc_message, { "method" => "autohand.pipe.output", "params" => payload })
    end

    assert_equal payloads, packets.map(&:params)
    assert_equal ["autohand.pipe.output"] * 3, packets.map(&:notification_method)
    assert_equal 3, typed.length
    remove.call
    transport.send(:handle_rpc_message, { "method" => "autohand.future", "params" => nil })

    assert_equal 3, packets.length
  end
end
