# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubygems/package"
require "rubocop/rake_task"
require "yard"

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

task default: %i[test rubocop]
