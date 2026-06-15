# CoachZed

CoachZed reads a workout catalog, asks an AI client for a day-by-day training plan, and writes schedule JSON plus calendar feeds.

## Configuration

You can set shared defaults with:

```ruby
CoachZed.configure do |config|
  config.workout_catalog_dir = "workouts"
  config.output_dir = "results"
end
```

`CoachZed.new` also loads defaults from either:

- `.coach_zed.yml` in the current directory
- `~/.config/coach_zed.yml`

If a config file is present, you can initialize with just `client:`.

Generated files are written beneath `output_dir`:

- `output_dir/schedules`
- `output_dir/feeds`

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. Releases are automated through GitHub Actions: conventional commits determine the next version, the workflow updates `lib/coach_zed/version.rb` and `CHANGELOG.md`, tags the release, builds the gem, and publishes the package to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/coach_zed. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/coach_zed/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the CoachZed project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/coach_zed/blob/main/CODE_OF_CONDUCT.md).
