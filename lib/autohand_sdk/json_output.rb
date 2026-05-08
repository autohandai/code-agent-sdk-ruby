# frozen_string_literal: true

require "json"

require_relative "errors"

module AutohandSDK
  module JsonOutput
    module_function

    def instruction(schema_name: nil, schema: nil, output_instructions: nil)
      parts = [
        "Return only valid JSON.",
        "Do not wrap the response in Markdown.",
        "Do not include commentary outside the JSON value."
      ]
      parts << "The JSON value should satisfy: #{schema_name}." if present?(schema_name)
      parts << "Use this JSON schema or example shape:\n#{JSON.pretty_generate(schema)}" unless schema.nil?
      parts << output_instructions if present?(output_instructions)
      parts.join("\n")
    end

    def parse(text, validate: nil)
      parsed = parse_json_text(text)
      validate ? validate.call(parsed) : parsed
    end

    def parse_json_text(text)
      raw = text.to_s
      trimmed = raw.strip
      raise StructuredOutputError.new("Expected JSON output, received an empty response.", raw) if trimmed.empty?

      direct = try_parse(trimmed)
      return direct unless direct.nil?

      fenced = parse_fenced_json(trimmed)
      return fenced unless fenced.nil?

      embedded = parse_embedded_json(trimmed)
      return embedded unless embedded.nil?

      raise StructuredOutputError.new("Expected valid JSON output from the agent.", raw)
    end

    def with_instruction(message, schema_name: nil, schema: nil, output_instructions: nil)
      [message,
       instruction(schema_name: schema_name, schema: schema, output_instructions: output_instructions)].join("\n\n")
    end

    def try_parse(candidate)
      JSON.parse(candidate)
    rescue JSON::ParserError
      nil
    end

    def parse_fenced_json(text)
      text.scan(/```(?:json)?\s*([\s\S]*?)\s*```/i).each do |match|
        parsed = try_parse(match.first.to_s.strip)
        return parsed unless parsed.nil?
      end
      nil
    end

    def parse_embedded_json(text)
      json_substrings(text).each do |candidate|
        parsed = try_parse(candidate)
        return parsed unless parsed.nil?
      end
      nil
    end

    def json_substrings(text)
      candidates = []
      stack = []
      start_index = nil
      in_string = false
      escaped = false

      text.each_char.with_index do |char, index|
        if in_string
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == "\""
            in_string = false
          end
          next
        end

        if char == "\""
          in_string = true
        elsif ["{", "["].include?(char)
          start_index = index if stack.empty?
          stack << char
        elsif ["}", "]"].include?(char) && !stack.empty?
          opener = stack.last
          matches = (opener == "{" && char == "}") || (opener == "[" && char == "]")
          unless matches
            stack.clear
            start_index = nil
            next
          end

          stack.pop
          if stack.empty? && start_index
            candidates << text[start_index..index]
            start_index = nil
          end
        end
      end

      candidates
    end

    def present?(value)
      !value.nil? && !value.to_s.empty?
    end
  end
end
