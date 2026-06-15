# frozen_string_literal: true

require_relative "lib/coach_zed/version"

Gem::Specification.new do |spec|
  spec.name = "coach_zed"
  spec.version = CoachZed::VERSION
  spec.authors = ["Ross Kaffenberger"]
  spec.email = ["rosskaff@gmail.com"]

  spec.summary = "Generate fitness schedules from a workout catalog."
  spec.description = "CoachZed reads a workout catalog, asks an AI client for a daily training plan, and writes schedule JSON plus calendar feeds."
  spec.homepage = "https://example.com/coach_zed"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://example.com/coach_zed/source"
  spec.metadata["changelog_uri"] = "https://example.com/coach_zed/changelog"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "sig/**/*", "README.md", "LICENSE.txt", "CHANGELOG.md"].sort
  end
  spec.require_paths = ["lib"]

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
