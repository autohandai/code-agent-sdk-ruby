# Rails Integration

The gem has no Rails runtime dependency. If Rails is present, the Railtie connects the SDK logger to `Rails.logger` unless you already configured another logger.

## Initializer

```ruby
# config/initializers/autohand_sdk.rb
AutohandSDK.configure do |config|
  config.cli_path = Rails.application.credentials.dig(:autohand, :cli_path)
  config.env_vars = {
    "AUTOHAND_NO_BANNER" => "1",
    "AUTOHAND_CLIENT_NAME" => "rails"
  }
end
```

## Background job

Keep jobs thin and delegate work to a model or domain method. The SDK block form keeps the subprocess lifecycle explicit:

```ruby
class RepositoryReviewJob < ApplicationJob
  queue_as :default

  def perform(repository)
    RepositoryReviewer.new(repository).review
  end
end

class RepositoryReviewer
  def initialize(repository)
    @repository = repository
  end

  def review
    AutohandSDK::Agent.open(cwd: @repository.path, instructions: "Return concise review findings.") do |agent|
      result = agent.run("Review this repository for production readiness")
      @repository.update!(latest_review: result.fetch(:text))
    end
  end
end
```

Avoid keeping a CLI subprocess in a long-lived global object unless you own the concurrency and shutdown behavior.
