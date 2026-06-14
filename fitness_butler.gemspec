# frozen_string_literal: true

require_relative "lib/fitness_butler/version"

Gem::Specification.new do |spec|
  spec.name = "fitness_butler"
  spec.version = FitnessButler::VERSION
  spec.authors = ["Ross Kaffenberger"]
  spec.email = ["rosskaff@gmail.com"]

  spec.summary = "Generate fitness schedules from a workout catalog."
  spec.description = "FitnessButler reads a workout catalog, asks an AI client for a daily training plan, and writes schedule JSON plus calendar feeds."
  spec.homepage = "https://example.com/fitness_butler"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://example.com/fitness_butler/source"
  spec.metadata["changelog_uri"] = "https://example.com/fitness_butler/changelog"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "sig/**/*", "README.md", "LICENSE.txt", "CHANGELOG.md"].sort
  end
  spec.require_paths = ["lib"]

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
