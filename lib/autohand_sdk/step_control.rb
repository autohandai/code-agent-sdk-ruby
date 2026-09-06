# frozen_string_literal: true

require_relative "rpc_types"

module AutohandSDK
  AgentStepToolCall = Data.define(:id, :tool, :args) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "step tool call")
      new(
        id: RPCValidation.optional_string(object["id"], "id")&.freeze,
        tool: RPCValidation.string(object.fetch("tool"), "tool").freeze,
        args: StepControl.freeze_json(RPCValidation.object(object.fetch("args"), "args"))
      )
    end
  end

  AgentStepToolResult = Data.define(:tool, :success, :output, :error) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "step tool result")
      new(
        tool: RPCValidation.string(object.fetch("tool"), "tool").freeze,
        success: RPCValidation.boolean(object.fetch("success"), "success"),
        output: RPCValidation.optional_string(object["output"], "output")&.freeze,
        error: RPCValidation.optional_string(object["error"], "error")&.freeze
      )
    end
  end

  AgentStep = Data.define(:step_number, :thought, :tool_calls, :tool_results) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "agent step")
      number = RPCValidation.integer(object.fetch("stepNumber"), "stepNumber")
      raise ArgumentError, "stepNumber must be positive" unless number.positive?

      calls = RPCValidation.array(object.fetch("toolCalls"), "toolCalls")
      results = RPCValidation.array(object.fetch("toolResults"), "toolResults")
      new(
        step_number: number,
        thought: RPCValidation.optional_string(object["thought"], "thought")&.freeze,
        tool_calls: calls.map { |call| AgentStepToolCall.from_rpc(call) }.freeze,
        tool_results: results.map { |result| AgentStepToolResult.from_rpc(result) }.freeze
      )
    end
  end

  StepEndEvent = Data.define(:step_id, :step, :timestamp) do
    def self.from_rpc(value)
      object = RPCValidation.object(value, "step end event")
      id = RPCValidation.string(object.fetch("stepId"), "stepId")
      raise ArgumentError, "stepId must be non-empty" if id.empty?

      new(step_id: id.freeze, step: AgentStep.from_rpc(object.fetch("step")),
          timestamp: RPCValidation.string(object.fetch("timestamp"), "timestamp").freeze)
    rescue KeyError, TypeError, ArgumentError => e
      raise RPCError, "Invalid stepEnd event: #{e.message}"
    end

    def type = "step_end"
    def method = "autohand.stepEnd"
  end

  # Immutable, ordered steps completed during the current prompt.
  StopConditionContext = Data.define(:steps)

  module StepControl
    module_function

    def prepare(params)
      wire = params.dup
      value = wire.delete("stop_when") || wire.delete("stopWhen")
      return [wire, []] if value.nil?

      conditions = value.is_a?(Array) ? value.dup : [value]
      unless conditions.all? { |condition| condition.respond_to?(:call) }
        raise ArgumentError, "stop_when must be a callable or an array of callables"
      end

      wire["stopWhen"] = { "mode" => "host" } unless conditions.empty?
      [wire, conditions.freeze]
    end

    def freeze_json(value)
      case value
      when Hash then value.transform_values { |item| freeze_json(item) }.freeze
      when Array then value.map { |item| freeze_json(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end

    # Stop after at least count completed tool steps in this prompt.
    def step_count(count)
      raise ArgumentError, "step count must be a positive integer" unless count.is_a?(Integer) && count.positive?

      ->(context) { context.steps.length >= count }
    end

    # Stop when the latest completed step called the named tool.
    def tool_call(name)
      raise ArgumentError, "tool name must be non-empty" unless name.is_a?(String) && !name.strip.empty?

      tool = name.strip.freeze
      ->(context) { context.steps.last&.tool_calls&.any? { |call| call.tool == tool } || false }
    end
  end
end
