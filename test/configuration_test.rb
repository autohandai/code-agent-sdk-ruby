# frozen_string_literal: true

require_relative "test_helper"

class ConfigurationTest < Minitest::Test
  def test_accepts_ruby_and_json_style_keys
    config = AutohandSDK::Configuration.new(
      "cliPath" => "/tmp/autohand",
      permissionMode: "interactive",
      appendSystemPrompt: "Prefer small commits",
      envVars: { AUTOHAND_NO_BANNER: 1 }
    )

    assert_equal("/tmp/autohand", config.cli_path)
    assert_equal("interactive", config.permission_mode)
    assert_equal("Prefer small commits", config.append_sys_prompt)
    assert_equal({ "AUTOHAND_NO_BANNER" => "1" }, config.env_vars)
  end

  def test_reads_nested_skill_settings
    config = AutohandSDK::Configuration.new(
      skills: {
        auto_skill: true,
        skills: ["ruby", "./skills/local/SKILL.md"],
        sources: [{ name: "team", path: "./skills" }],
        install_missing: true
      }
    )

    assert(config.auto_skill)
    assert_equal(["ruby", "./skills/local/SKILL.md"], config.skills)
    assert_equal([{ name: "team", path: "./skills" }], config.skill_sources)
    assert(config.install_missing_skills)
  end

  def test_validates_temperature
    assert_raises(AutohandSDK::ConfigurationError) do
      AutohandSDK::Configuration.new(temperature: 3.0)
    end
  end
end
