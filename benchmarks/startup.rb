#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"

WARMUPS = 5
SAMPLES = 50
BUDGET_MS = 50.0
ROOT = File.expand_path("..", __dir__)
LIB = File.join(ROOT, "lib")
FIXTURE_SOURCE = File.join(__dir__, "fake_rpc_cli.c")

def summarize(values)
  ordered = values.sort
  p95_ms = ordered[((0.95 * ordered.length).ceil - 1)].round(3)
  {
    samples: ordered.length,
    medianMs: ((ordered[24] + ordered[25]) / 2.0).round(3),
    p95Ms: p95_ms,
    maxMs: ordered.last.round(3),
    passed: p95_ms < BUDGET_MS,
    minMs: ordered.first.round(3),
    meanMs: (ordered.sum / ordered.length).round(3)
  }
end

def public_import_sample
  code = <<~RUBY
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    require "autohand_sdk"
    puts((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000.0)
  RUBY
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I#{LIB}", "-e", code, chdir: ROOT)
  raise "public import failed: #{stderr}" unless status.success?

  Float(stdout)
end

def sdk_start_sample(fixture_cli)
  client = AutohandSDK::Client.new(cli_path: fixture_cli, cwd: ROOT, timeout: 2_000, startup_check: true)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    client.start
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000.0
  ensure
    client.close
  end
end

def fixture_rpc_sample(fixture_cli)
  transport = AutohandSDK::Transport.new(cli_path: fixture_cli, cwd: ROOT, timeout: 2_000)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    transport.start
    transport.request("autohand.getState", {})
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000.0
  ensure
    transport.stop
  end
end

def collect(&sample)
  WARMUPS.times { sample.call }
  Array.new(SAMPLES) { sample.call }
end

def compile_fixture(directory)
  executable = File.join(directory, "autohand-ruby-startup-fixture")
  compiler = ENV.fetch("CC", "cc")
  stdout, stderr, status = Open3.capture3(compiler, "-O2", FIXTURE_SOURCE, "-o", executable)
  raise "native fixture compilation failed: #{stdout}#{stderr}" unless status.success?

  executable
end

require "autohand_sdk"

Dir.mktmpdir("autohand-ruby-startup-") do |directory|
  fixture_cli = compile_fixture(directory)
  metrics = {
    publicImportMs: summarize(collect { public_import_sample }),
    sdkStartReturnMs: summarize(collect { sdk_start_sample(fixture_cli) }),
    fixtureSpawnToFirstRpcMs: summarize(collect { fixture_rpc_sample(fixture_cli) })
  }
  passed = metrics.values.all? { |stats| stats.fetch(:passed) }
  result = {
    language: "ruby",
    budgetMs: BUDGET_MS,
    metrics: metrics,
    passed: passed,
    warmups: WARMUPS
  }
  puts JSON.pretty_generate(result)

  failures = metrics.filter_map { |name, stats| name unless stats.fetch(:passed) }
  abort "startup p95 gate failed: #{failures.join(", ")}" unless failures.empty?
end
