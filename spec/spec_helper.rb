# frozen_string_literal: true

require "openai"
require "coach_zed"

Dir[File.join(__dir__, "support/**/*.rb")].sort.each do |file|
  require file
end

RSpec.configure do |config|
  config.before do
    CoachZed.reset_config!
  end

  config.after do
    CoachZed.reset_config!
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
