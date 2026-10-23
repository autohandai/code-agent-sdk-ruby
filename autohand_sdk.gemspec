# frozen_string_literal: true

require_relative "lib/autohand_sdk/version"

Gem::Specification.new do |spec|
  spec.name = "autohand_sdk"
  spec.version = AutohandSDK::VERSION
  spec.authors = ["Autohand"]
  spec.email = ["support@autohand.ai"]

  spec.summary = "CLI-backed Autohand Code Agent SDK for Ruby."
  spec.description = [
    "A Ruby SDK for controlling Autohand Code CLI agents over JSON-RPC,",
    "with streaming events, permissions, sessions, skills, and Rails-friendly configuration."
  ].join(" ")
  spec.homepage = "https://autohand.ai/sdk/"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/autohandai/code-agent-sdk-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/autohandai/code-agent-sdk-ruby/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://autohand.ai/docs/agent-sdk/"
  spec.metadata["bug_tracker_uri"] = "https://github.com/autohandai/code-agent-sdk-ruby/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  tracked_files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.read.split("\x0")
  end
  fallback_files = Dir.chdir(__dir__) do
    Dir.glob(%w[
               lib/**/*.rb
               docs/**/*.md
               exe/*
               examples/**/*.rb
               README.md
               CHANGELOG.md
               LICENSE.txt
             ])
  end

  spec.files = (tracked_files.empty? ? fallback_files : tracked_files).reject do |file|
    file.start_with?(*%w[
                       .github/
                       test/
                       benchmarks/
                       tmp/
                       bin/
                       .bundle/
                       doc/
                       pkg/
                     ])
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |file| File.basename(file) }
  spec.require_paths = ["lib"]

  spec.add_dependency "logger", ">= 1.6", "< 2.0"
end
