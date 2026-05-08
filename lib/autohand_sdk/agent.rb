# frozen_string_literal: true

require "securerandom"

require_relative "client"
require_relative "json_output"

module AutohandSDK
  class Run
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
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def stream
      ensure_started

      Enumerator.new do |yielder|
        index = 0
        loop do
          event = nil
          @mutex.synchronize do
            @condition.wait(@mutex) while index >= @events.length && !@completed
            event = @events[index] if index < @events.length
            index += 1 if event
          end

          yielder << event if event

          finished, error = @mutex.synchronize { [@completed && index >= @events.length, @error] }
          raise error if finished && error
          break if finished
        end
      end
    end

    def wait
      ensure_started
      @thread.join
      raise @error if @error

      result
    end

    def json(validate: nil)
      JsonOutput.parse(wait.fetch(:text), validate: validate)
    end

    def abort
      @status = "aborted"
      @client.abort
    end

    private

    def ensure_started
      return if @started

      @started = true
      @thread = Thread.new { pump }
    end

    def pump
      @client.stream_prompt(@params).each { |event| record(event) }
    rescue StandardError => e
      @mutex.synchronize { @error = e }
    ensure
      @mutex.synchronize do
        @completed = true
        @condition.broadcast
      end
    end

    def record(event)
      @mutex.synchronize do
        @events << event
        event_type = event["type"]
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
