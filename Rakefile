# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubocop/rake_task"
require "yard"

desc "Run the test suite"
task :test do
  sh Gem.ruby, "-Ilib:test", "-e", 'Dir["test/**/*_test.rb"].sort.each { |file| require_relative file }'
end

RuboCop::RakeTask.new
YARD::Rake::YardocTask.new

task default: %i[test rubocop]
