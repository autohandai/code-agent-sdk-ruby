# frozen_string_literal: true

require "logger"

require_relative "errors"
require_relative "utils"

module AutohandSDK
  class Configuration
    ATTRIBUTES = %i[
      cwd cli_path debug timeout startup_check auto_mode unrestricted auto_skill model temperature max_iterations
      max_runtime max_cost sys_prompt append_sys_prompt yolo yolo_timeout add_dir extra_args skills skill_files
      skill_sources install_missing_skills permission_mode permission_allow_list permission_deny_list plan_mode
      persist_session session_id resume continue_session session_path auto_save_interval context_compact max_tokens
      compression_threshold summarization_threshold copy_skill_files provider api_key base_url autohand_ai_plan
      env_vars
    ].freeze

    attr_accessor :cwd, :cli_path, :debug, :timeout, :startup_check, :auto_mode, :unrestricted, :auto_skill,
                  :model, :temperature, :max_iterations, :max_runtime, :max_cost, :sys_prompt, :append_sys_prompt,
                  :yolo, :yolo_timeout, :add_dir, :extra_args, :skills, :skill_files, :skill_sources,
                  :install_missing_skills, :permission_mode, :permission_allow_list, :permission_deny_list,
                  :plan_mode, :persist_session, :session_id, :resume, :continue_session, :session_path,
                  :auto_save_interval, :context_compact, :max_tokens, :compression_threshold,
                  :summarization_threshold, :copy_skill_files, :provider, :api_key, :base_url, :autohand_ai_plan,
                  :env_vars
    attr_writer :logger

    def initialize(**options)
      raw_options = options
      options = Utils.normalize_hash(options)
      options = merge_nested_options(options)

      @cwd = options.fetch(:cwd, Dir.pwd)
      @cli_path = options[:cli_path]
      @debug = options.fetch(:debug, false)
      @timeout = options.fetch(:timeout, 300_000)
      @startup_check = options.fetch(:startup_check, true)
      @auto_mode = options[:auto_mode]
      @unrestricted = options[:unrestricted]
      @auto_skill = options[:auto_skill]
      @model = options[:model]
      @temperature = options[:temperature]
      @max_iterations = options[:max_iterations]
      @max_runtime = options[:max_runtime]
      @max_cost = options[:max_cost]
      @sys_prompt = options[:sys_prompt] || options[:system_prompt]
      @append_sys_prompt = options[:append_sys_prompt] || options[:append_system_prompt]
      @yolo = options[:yolo]
      @yolo_timeout = options[:yolo_timeout]
      @add_dir = Array(options[:add_dir] || options[:additional_directories])
      @extra_args = Array(options[:extra_args])
      @permission_mode = options[:permission_mode]
      @permission_allow_list = Array(options[:permission_allow_list])
      @permission_deny_list = Array(options[:permission_deny_list])
      @plan_mode = options[:plan_mode]
      @persist_session = options[:persist_session]
      @session_id = options[:session_id]
      @resume = options[:resume]
      @continue_session = options[:continue_session] || options[:continue]
      @session_path = options[:session_path]
      @auto_save_interval = options[:auto_save_interval]
      @context_compact = options[:context_compact]
      @max_tokens = options[:max_tokens]
      @compression_threshold = options[:compression_threshold] || options[:compact_threshold]
      @summarization_threshold = options[:summarization_threshold]
      @copy_skill_files = options.fetch(:copy_skill_files, true)
      @provider = options[:provider]&.to_s
      @api_key = options[:api_key]
      @base_url = options[:base_url]
      @autohand_ai_plan = options[:autohand_ai_plan]
      @env_vars = raw_env_vars(raw_options, options).transform_keys(&:to_s).transform_values(&:to_s)
      @logger = options[:logger]

      apply_skill_options(options)
      validate!
    end

    def self.from(config = nil, **)
      case config
      when nil
        new(**)
      when Configuration
        config.merge(**)
      when Hash
        new(**config, **)
      else
        raise ConfigurationError, "expected Configuration, Hash, or nil; got #{config.class}"
      end
    end

    def merge(**options)
      self.class.new(**to_h, **Utils.normalize_hash(options))
    end

    def to_h
      hash = ATTRIBUTES.to_h do |attribute|
        [attribute, public_send(attribute)]
      end
      hash[:logger] = @logger if @logger
      hash
    end

    def logger
      @logger ||= Logger.new($stderr)
    end

    def logger_configured?
      !@logger.nil?
    end

    private

    def raw_env_vars(raw_options, normalized_options)
      raw_options[:env_vars] ||
        raw_options["env_vars"] ||
        raw_options[:envVars] ||
        raw_options["envVars"] ||
        raw_options[:env] ||
        raw_options["env"] ||
        normalized_options[:env_vars] ||
        normalized_options[:env] ||
        {}
    end

    def merge_nested_options(options)
      merged = options.dup
      merge_section!(merged, :session)
      merge_section!(merged, :context)
      merge_permission_section!(merged)
      merged
    end

    def merge_section!(options, key)
      section = options[key]
      return options unless section.is_a?(Hash)

      options.merge!(section) { |_nested_key, outer, _inner| outer }
    end

    def merge_permission_section!(options)
      permissions = options[:permissions]
      return options unless permissions.is_a?(Hash)

      options[:permission_mode] ||= permissions[:mode]
      options[:permission_allow_list] ||= permissions[:allow_list]
      options[:permission_deny_list] ||= permissions[:deny_list]
      options
    end

    def apply_skill_options(options)
      raw_skills = options[:skill_refs] || options[:skills]

      if raw_skills.is_a?(Hash)
        @auto_skill = raw_skills[:auto_skill] unless raw_skills[:auto_skill].nil?
        @skill_sources = Array(raw_skills[:sources])
        @install_missing_skills = raw_skills[:install_missing] unless raw_skills[:install_missing].nil?
        @skills = Array(raw_skills[:skills])
      else
        @skill_sources = Array(options[:skill_sources])
        @install_missing_skills = options[:install_missing_skills]
        @skills = Array(raw_skills)
      end

      @skill_files = Array(options[:skill_files])
    end

    def validate!
      raise ConfigurationError, "timeout must be positive" unless timeout.to_i.positive?

      if temperature && !(0.0..2.0).cover?(temperature.to_f)
        raise ConfigurationError, "temperature must be between 0.0 and 2.0"
      end

      return unless provider == "autohandai" && api_key.to_s.empty?

      raise ConfigurationError, "Autohand AI provider requires api_key"
    end
  end
end
