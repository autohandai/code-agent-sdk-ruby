# frozen_string_literal: true

require_relative "test_helper"
require "autohand_sdk/runtime_settings"

class RuntimeSettingsTest < Minitest::Test
  def test_native_provider_fields
    {
      "anthropic" => ["apiKey", "baseUrl", nil, nil],
      "openai" => %w[apiKey baseUrl authMode api-key],
      "xai" => %w[apiKey baseUrl authMode api-key],
      "azure" => %w[apiKey baseUrl authMethod api-key],
      "bedrock" => %w[apiKey endpoint authMode bedrock-api-key],
      "vertexai" => ["authToken", "endpoint", nil, nil]
    }.each do |provider, (key, endpoint, auth, mode)|
      config = AutohandSDK::Configuration.new(provider: provider, api_key: "secret", base_url: "https://fixture.test")
      section = AutohandSDK::RuntimeSettings.build(config).fetch(provider)

      assert_equal "secret", section.fetch(key)
      assert_equal(provider == "vertexai" ? "fixture.test" : "https://fixture.test", section.fetch(endpoint))
      assert_equal mode, section.fetch(auth) if auth
    end
  end

  def test_defaults_false_and_literal_provider_ids
    raw = { "customProviders" => { "My.Provider" => { "models" => [nil, "one"] } } }
    config = AutohandSDK::Configuration.new(provider: "autohandai", features: { slash_goal: false }, run_settings: raw)
    result = AutohandSDK::RuntimeSettings.build(config)

    assert_equal({ "features" => { "slashGoal" => false }, **raw }, result)
    assert_equal raw, config.merge(debug: true).run_settings
    refute AutohandSDK::Transport.new(config).send(:build_environment).key?("AUTOHAND_AI_PLAN")
    assert_equal({ "customProviders" => { "My.Provider" => { "apiKey" => "secret" } } },
                 AutohandSDK::RuntimeSettings.build(AutohandSDK::Configuration.new(provider: "custom:My.Provider",
                                                                                   api_key: "secret")))
  end

  def test_rejects_ambiguous_credentials_and_unsafe_settings
    assert_raises(AutohandSDK::ConfigurationError) { AutohandSDK::RuntimeSettings.build(AutohandSDK::Configuration.new(api_key: "secret")) }
    assert_raises(AutohandSDK::ConfigurationError) { AutohandSDK::RuntimeSettings.build(AutohandSDK::Configuration.new(fork: true)) }
    assert_raises(AutohandSDK::ConfigurationError) do
      AutohandSDK::RuntimeSettings.build(AutohandSDK::Configuration.new(provider: "vertexai", base_url: "https://user:secret@fixture.test/v1"))
    end
    config = AutohandSDK::Configuration.new(run_settings: { "features" => { "constructor" => true } })
    assert_raises(AutohandSDK::ConfigurationError) { AutohandSDK::RuntimeSettings.build(config) }
  end

  def test_translates_current_session_arguments
    cli, directory = FakeCLI.create
    [[{ session_id: "saved", persist_session: true }, ["--sdk-session-reference", "saved"]],
     [{ continue_session: true }, ["--sdk-resume-last"]],
     [{ fork: "saved", session_id: "saved" }, ["--fork", "saved"]]].each do |options, expected|
      transport = AutohandSDK::Transport.new(AutohandSDK::Configuration.new(cli_path: cli, **options))

      assert_equal [cli, "--mode", "rpc", *expected], transport.send(:build_args)
    end
  ensure
    FileUtils.remove_entry(directory) if directory
  end
end
