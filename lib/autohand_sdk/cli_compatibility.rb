# frozen_string_literal: true

module AutohandSDK
  # Reject obsolete wrapper switches before launching a CLI process.
  module CliCompatibility
    UNSUPPORTED = %w[
      --agents-md
      --no-agents-md
      --agents-md-create
      --agents-md-auto-update
      --agents-md-path
      --auto-save-interval
      --compression-threshold
      --summarization-threshold
      --skills
      --skill-sources
      --install-missing-skills
      --permission-mode
      --permission-allow-list
      --permission-deny-list
    ].freeze
    SWITCHES = %w[
      --bare
      --offline
      --yes
      --y
      --dry-run
      --debug
      --auto-commit
      -c
      --unrestricted
      --restricted
      --plan
      --answer-only
      --setup-only
      --no-idle-logout
      --auto-skill
      --learn
      --learn-update
      --project
      --permissions
      --settings
      --traces-on
      --traces-off
      --login
      --logout
      --patch
      --acp
      --sdk-resume-last
      --tmux
      --auto-mode
      --no-worktree
      --interactive-on-complete
      --setup
      --about
      --feedback
      --cc
      --context-compact
      --no-cc
      --no-context-compact
      --ephemeral
    ].freeze

    module_function

    def validate(arguments)
      index = 0
      while index < arguments.length
        argument = arguments[index]
        if UNSUPPORTED.include?(argument)
          raise ConfigurationError,
                "#{argument} is unsupported by the current CLI; use a supported CLI option or runtime RPC instead"
        end

        index += SWITCHES.include?(argument) ? 1 : 2
      end
    end
  end
end
