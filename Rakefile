# frozen_string_literal: true

require "bundler/gem_tasks"
require "fileutils"
require "rubygems/package"
require "rubocop/rake_task"
require "yard"

require_relative "lib/autohand_sdk/version"

GEM_NAME = "autohand_sdk"
GITHUB_REPOSITORY = "autohandai/code-agent-sdk-ruby"

desc "Run the test suite"
task :test do
  sh Gem.ruby, "-Ilib:test", "-e", 'Dir["test/**/*_test.rb"].sort.each { |file| require_relative file }'
end

RuboCop::RakeTask.new
YARD::Rake::YardocTask.new

namespace :package do
  desc "Verify the built gem includes the public executable"
  task :verify do
    gem_path = Dir["autohand_sdk-*.gem"].max_by { |path| File.mtime(path) }
    abort "No built gem found. Run `gem build autohand_sdk.gemspec` first." unless gem_path

    spec = Gem::Package.new(gem_path).spec
    abort "Gem is missing exe/autohand-sdk" unless spec.files.include?("exe/autohand-sdk")
    abort "Gem is missing autohand-sdk executable" unless spec.executables.include?("autohand-sdk")
  end
end

namespace :release do
  desc "Configure RubyGems Trusted Publishing for this repository"
  task :trusted_publisher do
    args = ["exec", "configure_trusted_publisher", "rubygem", "--name", GEM_NAME]
    args.push("--otp", ENV.fetch("RUBYGEMS_OTP")) if ENV["RUBYGEMS_OTP"]
    args << GITHUB_REPOSITORY

    sh Gem.ruby, "-S", "gem", *args
  end

  desc "Run checks, create the vVERSION tag, and push it to trigger RubyGems publishing"
  task :tag do
    tag = "v#{AutohandSDK::VERSION}"

    abort "Working tree must be clean before tagging a release." unless clean_worktree?

    sh "git", "fetch", "origin", "main", "--tags"
    abort "Tag #{tag} already exists locally." if local_tag_exists?(tag)
    abort "Tag #{tag} already exists on origin." if remote_tag_exists?(tag)

    sh Gem.ruby, "-S", "bundle", "exec", "rake"
    sh Gem.ruby, "-S", "bundle", "exec", "yard"
    FileUtils.rm_f(Dir["#{GEM_NAME}-*.gem"])
    sh Gem.ruby, "-S", "gem", "build", "#{GEM_NAME}.gemspec"
    sh Gem.ruby, "-S", "bundle", "exec", "rake", "package:verify"

    sh "git", "tag", "-a", tag, "-m", "Release #{tag}"
    sh "git", "push", "origin", "main"
    sh "git", "push", "origin", tag
  end
end

task default: %i[test rubocop]

def clean_worktree?
  `git status --porcelain`.strip.empty?
end

def local_tag_exists?(tag)
  system("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag}", out: File::NULL)
end

def remote_tag_exists?(tag)
  system("git", "ls-remote", "--exit-code", "--tags", "origin", tag, out: File::NULL)
end
