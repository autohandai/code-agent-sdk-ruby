# frozen_string_literal: true

# The immutable discovery wire values form one cohesive public contract.
# rubocop:disable Metrics/ModuleLength
module AutohandSDK
  module RPCValue
    module_function

    def optional_array(hash, key)
      value = hash[key]
      value.nil? ? nil : Array(value).map(&:to_s).freeze
    end

    def optional_hash(hash, key)
      value = hash[key]
      value.nil? ? nil : value.to_h.transform_keys(&:to_s).transform_values(&:to_s).freeze
    end
  end

  CommunitySkill = Data.define(
    :id,
    :name,
    :description,
    :category,
    :tags,
    :rating,
    :download_count,
    :featured,
    :curated
  ) do
    def self.from_rpc(value)
      new(
        id: value.fetch("id").to_s,
        name: value.fetch("name").to_s,
        description: value.fetch("description").to_s,
        category: value.fetch("category").to_s,
        tags: RPCValue.optional_array(value, "tags"),
        rating: value["rating"],
        download_count: value["downloadCount"],
        featured: value["isFeatured"],
        curated: value["isCurated"]
      )
    end

    alias_method :featured?, :featured
    alias_method :curated?, :curated
  end

  SkillRegistryCategory = Data.define(:name, :count) do
    def self.from_rpc(value)
      new(name: value.fetch("name").to_s, count: Integer(value.fetch("count")))
    end
  end

  SkillsRegistryResult = Data.define(:success, :skills, :categories, :error) do
    def self.from_rpc(value)
      new(
        success: value.fetch("success"),
        skills: Array(value["skills"]).map { |skill| CommunitySkill.from_rpc(skill) }.freeze,
        categories: Array(value["categories"]).map { |category| SkillRegistryCategory.from_rpc(category) }.freeze,
        error: value["error"]
      )
    end

    alias_method :success?, :success
  end

  InstallSkillResult = Data.define(:success, :skill_name, :path, :error) do
    def self.from_rpc(value)
      new(
        success: value.fetch("success"),
        skill_name: value["skillName"],
        path: value["path"],
        error: value["error"]
      )
    end

    alias_method :success?, :success
  end

  McpServerSummary = Data.define(:name, :status, :tool_count) do
    def self.from_rpc(value)
      new(
        name: value.fetch("name").to_s,
        status: value.fetch("status").to_s,
        tool_count: Integer(value.fetch("toolCount"))
      )
    end
  end

  McpServersResult = Data.define(:servers) do
    def self.from_rpc(value)
      new(servers: Array(value["servers"]).map { |server| McpServerSummary.from_rpc(server) }.freeze)
    end
  end

  McpTool = Data.define(:name, :description, :server_name) do
    def self.from_rpc(value)
      new(
        name: value.fetch("name").to_s,
        description: value.fetch("description").to_s,
        server_name: value.fetch("serverName").to_s
      )
    end
  end

  McpToolsResult = Data.define(:tools) do
    def self.from_rpc(value)
      new(tools: Array(value["tools"]).map { |tool| McpTool.from_rpc(tool) }.freeze)
    end
  end

  McpServerConfig = Data.define(
    :name,
    :transport,
    :command,
    :args,
    :url,
    :env,
    :headers,
    :auto_connect
  ) do
    def self.from_rpc(value)
      transport = value.fetch("transport").to_s
      raise ArgumentError, "unsupported MCP transport: #{transport}" unless %w[stdio sse http].include?(transport)

      new(
        name: value.fetch("name").to_s,
        transport: transport,
        command: value["command"],
        args: RPCValue.optional_array(value, "args"),
        url: value["url"],
        env: RPCValue.optional_hash(value, "env"),
        headers: RPCValue.optional_hash(value, "headers"),
        auto_connect: value["autoConnect"]
      )
    end

    alias_method :auto_connect?, :auto_connect
  end

  McpServerConfigsResult = Data.define(:configs) do
    def self.from_rpc(value)
      new(configs: Array(value["configs"]).map { |config| McpServerConfig.from_rpc(config) }.freeze)
    end
  end
end
# rubocop:enable Metrics/ModuleLength
