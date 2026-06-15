# Fitness Butler

- Ruby gem repo for the reusable schedule-generation library.
- Public API: `CoachZed.new(workout_catalog_dir:, client:, model: "gpt-4.1", ...)`.
- Supported raw client: `OpenAI::Client`; it is wrapped internally. Unsupported clients should raise during initialization.
- Do not add `ruby-openai` as a gemspec runtime dependency unless the public API changes again.
- Keep the gem focused on parsing the workout catalog, building prompts, parsing JSON schedules, and writing `.ics` / `.webcal` feeds.
- Use `standardrb` and `rspec` for verification.
- The release workflow is driven from GitHub Actions and uses conventional commits plus `git-mkver`.
