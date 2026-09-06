# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "timeout"

class StepControlTest < SDKTestCase
  def setup
    super
    @request_log = File.join(@cli_dir, "requests.jsonl")
    File.write(@cli_path, File.read(File.join(__dir__, "fixtures/step_control_cli.rb")))
    @agent = AutohandSDK::Agent.create(
      cli_path: @cli_path, timeout: 2_000,
      env_vars: { "AUTOHAND_TEST_REQUEST_LOG" => @request_log }
    )
  end

  def teardown
    @agent&.close
    super
  end

  def test_stop_after_persisted_steps_and_continue_on_the_same_session
    snapshots = []
    observer = lambda do |context|
      snapshots << context
      false
    end
    run = @agent.send("steps", stop_when: [observer, AutohandSDK.is_step_count(2)])
    result = within { run.wait }

    assert_equal("stopped", result.fetch(:status))
    assert_equal([1, 2], result.fetch(:steps).map(&:step_number))
    assert_equal("persisted evidence 2", result.fetch(:steps).last.tool_results.first.output)
    assert_equal([1, 2], snapshots.map { |context| context.steps.length })
    assert_equal(result, run.wait)
    assert_equal(result.fetch(:events), run.stream.to_a)
    assert_equal({ "mode" => "host" }, requests("prompt").first.fetch("params").fetch("stopWhen"))
    assert_equal([false, true], requests("stepDecision").map { |request| request.fetch("params").fetch("stop") })
    assert_empty(requests("abort"))
    assert_equal("persisted evidence", within { @agent.run("continue") }.fetch(:text))
  end

  def test_tool_helper_and_invalid_inputs
    [0, -1, 1.5, "2"].each { |count| assert_raises(ArgumentError) { AutohandSDK.is_step_count(count) } }
    ["", " ", nil].each { |name| assert_raises(ArgumentError) { AutohandSDK.has_tool_call(name) } }
    result = within { @agent.run("steps", stop_when: AutohandSDK.has_tool_call(" read_file ")) }

    assert_equal("stopped", result.fetch(:status))
    assert_equal(1, result.fetch(:steps).length)
  end

  def test_predicate_failure_stops_before_surfacing_without_an_extra_abort
    failure = RuntimeError.new("predicate failed")
    run = @agent.send("steps", stop_when: ->(_) { raise failure })
    error = assert_raises(RuntimeError) { within { run.wait } }

    assert_same(failure, error)
    assert_same(error, assert_raises(RuntimeError) { run.wait })
    assert_equal([true], requests("stepDecision").map { |request| request.fetch("params").fetch("stop") })
    assert_empty(requests("abort"))
    assert_equal("persisted evidence", within { @agent.run("continue") }.fetch(:text))
  end

  def test_terminal_reasons_are_preserved
    assert_equal("aborted", within { @agent.run("aborted") }.fetch(:status))
    assert_equal("failed", within { @agent.run("error") }.fetch(:status))
    assert_equal("completed", within { @agent.run("continue") }.fetch(:status))
  end

  def test_stream_cancellation_preserves_an_observed_failure
    run = @agent.send("pending_error")
    event = within { run.stream.find { |item| item["type"] == "error" } }

    assert_equal("model failed before cancellation", event.fetch("message"))
    assert_equal("failed", run.wait.fetch(:status))
  end

  def test_unstarted_queued_and_completed_run_abort_cannot_cancel_another_turn
    entered = Queue.new
    release = Queue.new
    first = @agent.send("steps", stop_when: lambda { |_context|
      entered << true
      release.pop
    })
    first_waiter = Thread.new { first.wait }
    within { entered.pop }

    unstarted = @agent.send("must not submit")
    unstarted.abort

    assert_equal("aborted", within { unstarted.wait }.fetch(:status))

    queued = @agent.send("also must not submit")
    queued_waiter = Thread.new { queued.wait }
    wait_until { queued.instance_variable_get(:@started) }
    within { queued.abort }

    assert_equal("aborted", within { queued_waiter.value }.fetch(:status))
    assert_equal(["steps"], requests("prompt").map { |request| request.fetch("params").fetch("message") })
    assert_empty(requests("abort"))

    release << true

    assert_equal("stopped", within { first_waiter.value }.fetch(:status))
    first.abort

    assert_empty(requests("abort"))
    assert_equal("completed", within { @agent.run("continue") }.fetch(:status))
  ensure
    release << true if release
    first_waiter&.kill
    queued_waiter&.kill
  end

  def test_abort_cancels_a_pending_predicate_and_drains_the_active_turn
    entered = Queue.new
    cancelled = Queue.new
    run = @agent.send("steps", stop_when: lambda { |_context|
      entered << true
      begin
        sleep
      ensure
        cancelled << true
      end
    })
    waiter = Thread.new { run.wait }
    within { entered.pop }
    within { run.abort }

    assert(within { cancelled.pop })
    assert_equal("aborted", within { waiter.value }.fetch(:status))
    assert_equal(1, requests("abort").length)
    assert_equal("persisted evidence", within { @agent.run("continue") }.fetch(:text))
  ensure
    waiter&.kill
  end

  def test_malformed_steps_and_rejected_decisions_settle_before_reuse
    %w[malformed reject_decision].each do |message|
      assert_raises(AutohandSDK::Error) do
        within { @agent.run(message, stop_when: ->(_) { true }) }
      end
      assert_equal("persisted evidence", within { @agent.run("continue") }.fetch(:text))
    end
    assert_equal(2, requests("abort").length)
  end

  def test_abort_deadline_terminates_an_unresponsive_turn_and_allows_restart
    entered = Queue.new
    run = @agent.send("ignore_abort", stop_when: lambda { |_context|
      entered << true
      sleep
    })
    waiter = Thread.new { run.wait }
    within { entered.pop }
    within { run.abort }

    assert_equal("aborted", within { waiter.value }.fetch(:status))
    assert_equal("completed", within { @agent.run("continue") }.fetch(:status))
  ensure
    waiter&.kill
  end

  def test_rejected_prompt_does_not_abort_an_idle_session
    assert_raises(AutohandSDK::RPCError) { within { @agent.run("reject") } }
    assert_empty(requests("abort"))
    assert_equal("completed", within { @agent.run("continue") }.fetch(:status))
  end

  def test_prompt_overflow_fails_instead_of_dropping_events
    rpc = @agent.instance_variable_get(:@client).instance_variable_get(:@rpc_client)
    error = assert_raises(AutohandSDK::TransportError) do
      within do
        @agent.stream_prompt("flood").each do |_event|
          wait_until { rpc.instance_variable_get(:@prompt_context).queue.closed? }
        end
      end
    end

    assert_match(/overflow/, error.message)
    assert_equal("completed", within { @agent.run("continue") }.fetch(:status))
  end

  def test_client_prompt_serializes_with_streaming_runs_and_accepts_stop_conditions
    entered = Queue.new
    release = Queue.new
    first = Thread.new do
      @agent.run("steps", stop_when: lambda { |_context|
        entered << true
        release.pop
      })
    end
    within { entered.pop }
    second = Thread.new { @agent.prompt("continue") }
    wait_until { second.status == "sleep" }

    assert_equal(1, requests("prompt").length)

    release << true

    assert_equal("stopped", within { first.value }.fetch(:status))
    assert_equal({ "success" => true }, within { second.value })
    assert_equal({ "success" => true }, within { @agent.prompt("steps", stop_when: ->(_) { true }) })
  ensure
    release << true if release
    first&.kill
    second&.kill
  end

  private

  def requests(method)
    return [] unless File.exist?(@request_log)

    log = File.readlines(@request_log).map { |line| JSON.parse(line) }
    log.select { |request| request["method"] == "autohand.#{method}" }
  end

  def within(&)
    Timeout.timeout(4, &)
  end

  def wait_until
    within { Thread.pass until yield }
  end
end
