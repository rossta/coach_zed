# Fitness Butler

- Ruby gem repo for the reusable schedule-generation library.
- Public API: `CoachZed.new(workout_catalog_dir:, client:, model: "gpt-4.1", ...)`.
- Supported raw client: `OpenAI::Client`; it is wrapped internally. Unsupported clients should raise during initialization.
- Do not add `ruby-openai` as a gemspec runtime dependency unless the public API changes again.
- Keep the gem focused on parsing the workout catalog, building prompts, parsing JSON schedules, and writing `.ics` / `.webcal` feeds.
- Use `standardrb` and `rspec` for verification.
- The release workflow is driven from GitHub Actions and uses conventional commits plus `git-mkver`.

## Ruby

- Use the Ruby version in `.ruby-version` for any Ruby commands.
- If `chruby` is available on the system, activate the configured `.ruby-version` with `chruby` before running Ruby commands.
- If `chruby` is installed via Homebrew, load it first and then switch to the repo Ruby before running `bundle`, `rspec`, `standardrb`, or other Ruby commands.
