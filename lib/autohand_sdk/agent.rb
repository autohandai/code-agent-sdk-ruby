# frozen_string_literal: true

require "securerandom"

require_relative "client"
require_relative "json_output"

module AutohandSDK
  class Run
    PUMP_CANCEL_TIMEOUT = 5.0
    PUMP_FORCE_JOIN_TIMEOUT = 1.0
    PUMP_THREAD_PREFIX = "autohand-sdk-run-"

    class PumpCancelled < StandardError; end

    attr_reader :id

    def initialize(client, params, id: nil)
      @client = client
      @params = params
      @id = id || "run_#{Time.now.to_i.to_s(36)}_#{SecureRandom.hex(4)}"
      @events = []
      @text = +""
      @status = "completed"
      @started = false
      @completed = false
      @error = nil
      @active_streams = 0
      @waiters = 0
      @cancel_requested = false
      @prompt_stream = nil
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def stream
      ensure_started

      Enumerator.new do |yielder|
        index = 0
        settled = false
        register_stream
        begin
          loop do
            event = nil
            @mutex.synchronize do
              @condition.wait(@mutex) while index >= @events.length && !@completed
              event = @events[index] if index < @events.length
              index += 1 if event
            end

            yielder << event if event

            finished, error = @mutex.synchronize { [@completed && index >= @events.length, @error] }
            next unless finished

            settled = true
            raise error if error

            break
          end
        ensure
          cancel_pump(unregister_stream(settled))
        end
      end
    end

    def wait
      thread = register_waiter
      begin
        thread.join
      ensure
        @mutex.synchronize { @waiters -= 1 }
      end
      error = @mutex.synchronize { @error }
      raise error if error

      result
    end

    def json(validate: nil)
      JsonOutput.parse(wait.fetch(:text), validate: validate)
    end

    def abort
      @mutex.synchronize { @status = "aborted" }
      @client.abort
    end

    private

    def ensure_started
      @mutex.synchronize { start_pump unless @started }
    end

    def start_pump
      @started = true
      @thread = Thread.new { pump }
      @thread.name = "#{PUMP_THREAD_PREFIX}#{@id}" if @thread.respond_to?(:name=)
    end

    def register_stream
      @mutex.synchronize do
        start_pump unless @started
        @active_streams += 1
      end
    end

    def unregister_stream(settled)
      @mutex.synchronize do
        @active_streams -= 1
        return unless abandon_pump?(settled)

        @cancel_requested = true
        @status = "aborted"
        @thread
      end
    end

    def abandon_pump?(settled)
      !settled && @active_streams.zero? && @waiters.zero? && !@completed && !@cancel_requested
    end

    def register_waiter
      @mutex.synchronize do
        start_pump unless @started
        @waiters += 1
        @thread
      end
    end

    def cancel_pump(thread)
      return unless thread&.alive?

      # Enumerator has no close API; unwinding it on its owning thread runs the
      # low-level prompt ensure block, which aborts and drains the active turn.
      thread.raise(PumpCancelled)
      return if thread.join(PUMP_CANCEL_TIMEOUT)

      @client.close
      thread.kill
      thread.join(PUMP_FORCE_JOIN_TIMEOUT)
    rescue ThreadError
      thread&.join(PUMP_FORCE_JOIN_TIMEOUT)
    rescue StandardError
      thread.kill if thread&.alive?
      thread&.join(PUMP_FORCE_JOIN_TIMEOUT)
    ensure
      raise TransportError, "Prompt pump did not terminate after stream cancellation" if thread&.alive?
    end

    def pump
      prompt_stream = @client.stream_prompt(@params)
      @mutex.synchronize { @prompt_stream = prompt_stream }
      prompt_stream.each { |event| record(event) }
    rescue PumpCancelled
      nil
    rescue StandardError => e
      @mutex.synchronize { @error = e }
    ensure
      @mutex.synchronize do
        @prompt_stream = nil
        @completed = true
        @condition.broadcast
      end
    end

    def record(event)
      @mutex.synchronize do
        @events << event
        event_type = event.respond_to?(:type) ? event.type : event["type"]
        if event_type == "message_update"
          @text << event["delta"].to_s
        elsif event_type == "message_end" && event.key?("content")
          @text = event["content"].to_s
        end
        @condition.broadcast
      end
    end

    def result
      @mutex.synchronize do
        {
          id: @id,
          status: @status,
          text: @text.dup,
          events: @events.dup
        }
      end
    end
  end

  class Agent
    def initialize(client)
      @client = client
    end

    def self.create(config = nil, instructions: nil, **)
      config = Configuration.from(config, **)
      if instructions && !instructions.empty?
        config.append_sys_prompt = [config.append_sys_prompt, instructions].compact.reject(&:empty?).join("\n\n")
      end
      client = Client.new(config)
      client.start
      new(client)
    end

    def self.open(config = nil, **)
      agent = create(config, **)
      return agent unless block_given?

      begin
        yield agent
      ensure
        agent.close
      end
    end

    def self.from_client(client)
      new(client)
    end

    def send(input, **)
      Run.new(@client, prompt_params(input, **))
    end

    def run(input, **)
      send(input, **).wait
    end

    def run_json(input, schema_name: nil, schema: nil, output_instructions: nil, validate: nil, **)
      params = prompt_params(input, **)
      params["message"] = JsonOutput.with_instruction(
        params.fetch("message"),
        schema_name: schema_name,
        schema: schema,
        output_instructions: output_instructions
      )
      Run.new(@client, params).json(validate: validate)
    end

    def stream(input, **, &block)
      events = send(input, **).stream
      return events unless block

      events.each(&block)
    end

    def command(command, args = nil, **options)
      send(Utils.format_slash_command(command, args), **options)
    end

    def deep_research(topic, **options)
      command("/deep-research", topic, **options)
    end

    def autoresearch(objective, **options)
      command("/autoresearch", objective, **options)
    end

    def close
      @client.close
    end

    def method_missing(method_name, ...)
      if @client.respond_to?(method_name)
        @client.public_send(method_name, ...)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @client.respond_to?(method_name, include_private) || super
    end

    private

    def prompt_params(input, **options)
      if input.is_a?(Hash)
        Utils.with_rpc_aliases(Utils.normalize_hash(input).merge(Utils.normalize_hash(options)))
      else
        Utils.with_rpc_aliases({ message: input.to_s }.merge(Utils.normalize_hash(options)))
      end
    end
  end
end
