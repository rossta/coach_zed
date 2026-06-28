# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"
require "time"
require "yaml"

require_relative "coach_zed/version"
require_relative "coach_zed/catalog"
require_relative "coach_zed/clients/ruby_openai"
require_relative "coach_zed/feed_reader"
require_relative "coach_zed/feed_writer"
require_relative "coach_zed/schedule_schema"
require_relative "coach_zed/prompt_builder"
require_relative "coach_zed/schedule_parser"

class CoachZed
  Result = Data.define(:schedule_path, :ics_path, :webcal_path, :schedule)

  class Config
    attr_accessor :workout_catalog_dir, :model, :output_dir, :feed_output_basename, :feed_title, :existing_feed_path, :existing_schedule_path, :merge_policy

    def initialize(
      workout_catalog_dir: nil,
      model: nil,
      output_dir: nil,
      feed_output_basename: nil,
      feed_title: nil,
      existing_feed_path: nil,
      existing_schedule_path: nil,
      merge_policy: nil
    )
      @workout_catalog_dir = workout_catalog_dir
      @model = model
      @output_dir = output_dir
      @feed_output_basename = feed_output_basename
      @feed_title = feed_title
      @existing_feed_path = existing_feed_path
      @existing_schedule_path = existing_schedule_path
      @merge_policy = merge_policy
    end

    def apply(hash)
      hash.each do |key, value|
        public_send("#{key}=", value) if respond_to?("#{key}=")
      end
    end
  end

  class << self
    def config
      @config ||= default_config
      load_config_file
      @config
    end

    def configure
      load_config_file
      yield config
    end

    def load_config_file
      return if @config_file_loaded

      @config ||= default_config

      config_file_paths.each do |path|
        next unless File.exist?(path)

        parsed = YAML.load_file(path)
        next unless parsed.is_a?(Hash)

        @config.apply(parsed.transform_keys(&:to_sym))
        @config_file_loaded = true
        return path
      end

      @config_file_loaded = true
      nil
    end

    def reset_config!
      @config = nil
      @config_file_loaded = false
    end

    def default_config
      Config.new(
        model: "gpt-4.1",
        output_dir: "results"
      )
    end

    def config_file_paths
      [".coach_zed.yml", File.expand_path("~/.config/coach_zed.yml")]
    end
  end

  def initialize(
    client:,
    workout_catalog_dir: nil,
    model: nil,
    output_dir: nil,
    feed_output_basename: nil,
    feed_title: nil,
    existing_feed_path: nil,
    existing_schedule_path: nil,
    merge_policy: nil
  )
    config = self.class.config

    @workout_catalog_dir = Pathname(workout_catalog_dir || config.workout_catalog_dir || raise(ArgumentError, "workout_catalog_dir is required"))
    model_name = model || config.model || "gpt-4.1"
    @ai_client = wrap_client(client, model: model_name)
    @output_dir = Pathname(output_dir || config.output_dir || "results")
    @schedule_output_dir = @output_dir.join("schedules")
    @feed_output_dir = @output_dir.join("feeds")
    @feed_output_basename = feed_output_basename.nil? ? config.feed_output_basename : feed_output_basename
    @feed_title = feed_title.nil? ? config.feed_title : feed_title
    resolved_existing_feed_path = existing_feed_path.nil? ? config.existing_feed_path : existing_feed_path
    @existing_feed_path = resolved_existing_feed_path && Pathname(resolved_existing_feed_path)
    resolved_existing_schedule_path = existing_schedule_path.nil? ? config.existing_schedule_path : existing_schedule_path
    resolved_existing_schedule_path =
      if resolved_existing_schedule_path.nil? && @existing_feed_path
        Pathname(@existing_feed_path.to_s.sub(/\.ics\z/, ".json"))
      else
        resolved_existing_schedule_path
      end
    @existing_schedule_path = resolved_existing_schedule_path && Pathname(resolved_existing_schedule_path)
    @merge_policy = merge_policy.nil? ? config.merge_policy : merge_policy
  end

  def generate_schedule(start_date:, consultation_prompt: nil, consultation_prompt_path: nil, generation_mode: nil, merge_policy: nil)
    prompt_text = resolve_prompt_text(consultation_prompt, consultation_prompt_path)
    catalog = Catalog::Loader.new(@workout_catalog_dir).load
    generation_mode = normalize_generation_mode(generation_mode)
    merge_policy = normalize_merge_policy(merge_policy || @merge_policy || generation_mode)
    existing_schedule = load_existing_schedule if merge_policy == :append
    existing_feed = load_existing_feed if existing_schedule.nil? && generation_mode != :refresh
    start_date = generation_start_date(start_date, existing_schedule:, generation_mode:, merge_policy:)
    generation_days = generation_days_for(start_date, generation_mode:, existing_schedule:, merge_policy:)
    existing_context = existing_schedule ? schedule_context(existing_schedule, limit_days: 28) : existing_feed&.to_context(limit_days: 28)
    schedule_key = schedule_key_for(prompt_text, start_date, catalog, generation_days, existing_context, merge_policy)
    prompt = PromptBuilder.new(
      consultation_prompt: prompt_text,
      catalog: catalog,
      start_date: start_date,
      schedule_key: schedule_key,
      generation_days: generation_days,
      existing_feed_context: existing_context
    ).build
    raw_schedule = @ai_client.generate(prompt:)
    schedule = ScheduleParser.parse(raw_schedule)
    schedule = normalize_schedule(schedule, start_date:, prompt_text:, schedule_key:, catalog:, generation_days:, merge_policy:)
    schedule = merge_schedule(existing_schedule, schedule, merge_policy)

    schedule_path = write_schedule(schedule, schedule_key)
    feed_paths = write_feeds(schedule)

    Result.new(
      schedule_path: schedule_path,
      ics_path: feed_paths.fetch(:ics),
      webcal_path: feed_paths.fetch(:webcal),
      schedule: schedule
    )
  end

  private

  attr_reader :workout_catalog_dir, :ai_client, :output_dir, :schedule_output_dir, :feed_output_dir, :feed_output_basename, :feed_title, :existing_feed_path, :existing_schedule_path, :merge_policy

  def wrap_client(client, model:)
    return client if client.is_a?(Clients::RubyOpenAI)

    client_name = client.class.name
    if client_name == "OpenAI::Client"
      return Clients::RubyOpenAI.new(client:, model:)
    end

    raise ArgumentError, "unsupported client: #{client_name || client.class}"
  end

  def resolve_prompt_text(consultation_prompt, consultation_prompt_path)
    if consultation_prompt && consultation_prompt_path
      raise ArgumentError, "provide either consultation_prompt or consultation_prompt_path, not both"
    end

    if consultation_prompt.nil? && consultation_prompt_path.nil?
      raise ArgumentError, "provide consultation_prompt or consultation_prompt_path"
    end

    return consultation_prompt if consultation_prompt

    Pathname(consultation_prompt_path.to_s).read
  end

  def normalize_date(value)
    case value
    when Date
      value
    when Time, DateTime
      value.to_date
    else
      Date.parse(value.to_s)
    end
  end

  def load_existing_feed
    return nil if existing_feed_path.nil?
    return nil unless existing_feed_path.exist?

    FeedReader.load_existing(existing_feed_path)
  end

  def load_existing_schedule
    return nil if existing_schedule_path.nil?
    return nil unless existing_schedule_path.exist?

    schedule = JSON.parse(existing_schedule_path.read)
    ScheduleParser.validate!(schedule)
    schedule
  end

  def normalize_generation_mode(value)
    return nil if value.nil?

    case value.to_sym
    when :refresh, :append
      value.to_sym
    else
      raise ArgumentError, "unsupported generation mode: #{value}"
    end
  end

  def normalize_merge_policy(value)
    return :replace if value.nil?

    case value.to_sym
    when :replace, :append
      value.to_sym
    else
      raise ArgumentError, "unsupported merge policy: #{value}"
    end
  end

  def generation_start_date(start_date, existing_schedule:, generation_mode:, merge_policy:)
    return normalize_date(start_date) if generation_mode == :refresh

    if merge_policy == :append
      last_date = existing_schedule&.fetch("days")&.map { |day| Date.parse(day.fetch("date")) }&.max
      return normalize_date(start_date) if last_date.nil?

      last_date + 1
    else
      normalize_date(start_date)
    end
  end

  def generation_days_for(start_date, generation_mode:, existing_schedule:, merge_policy:)
    return 7 if merge_policy == :append && existing_schedule
    return 28 if merge_policy == :append
    return 28 if generation_mode.nil?

    upcoming_sunday = start_date + ((7 - start_date.wday) % 7)
    (upcoming_sunday - start_date).to_i + 29
  end

  def schedule_key_for(prompt_text, start_date, catalog, generation_days, existing_context, merge_policy)
    Digest::SHA256.hexdigest(
      [
        prompt_text.strip,
        start_date.iso8601,
        generation_days,
        catalog_digest(catalog),
        merge_policy.to_s,
        existing_context.to_s
      ].join("\n")
    )[0...12] || ""
  end

  def catalog_digest(catalog)
    Digest::SHA256.hexdigest(catalog.map(&:fingerprint).join("\n"))
  end

  def normalize_schedule(schedule, start_date:, prompt_text:, schedule_key:, catalog:, generation_days:, merge_policy:)
    catalog_texts = catalog.to_h { |entry| [entry.relative_path, entry.path.read] }
    days = schedule.fetch("days")
    normalized_days = days.each_with_index.map do |day, index|
      day_number = day.fetch("day_number", index + 1).to_i
      date = start_date + (day_number - 1)
      workout = day["workout"]
      workout = workout&.merge("catalog_text" => catalog_texts.fetch(workout["catalog_path"], ""))
      {
        "day_number" => day_number,
        "date" => date.iso8601,
        "day_type" => day.fetch("day_type"),
        "workout" => workout&.transform_keys(&:to_s),
        "notes" => day["notes"].to_s
      }
    end

    schedule.merge(
      "schema_version" => 1,
      "schedule_id" => schedule_key,
      "start_date" => start_date.iso8601,
      "consultation_prompt" => prompt_text,
      "catalog_directory" => workout_catalog_dir.to_s,
      "catalog_count" => catalog.count,
      "program_length_days" => schedule.fetch("program_length_days", generation_days).to_i,
      "merge_policy" => merge_policy.to_s,
      "generated_at" => Time.now.utc.iso8601,
      "days" => normalized_days
    )
  end

  def merge_schedule(existing_schedule, schedule, merge_policy)
    return schedule if merge_policy == :replace || existing_schedule.nil?

    existing_by_date = existing_schedule.fetch("days").to_h { |day| [day.fetch("date"), day] }
    merged_by_date = existing_by_date.merge(schedule.fetch("days").to_h { |day| [day.fetch("date"), day] })

    merged_days = merged_by_date.values.sort_by { |day| Date.parse(day.fetch("date")) }
    merged_days = merged_days.each_with_index.map do |day, index|
      day.merge("day_number" => index + 1)
    end

    schedule.merge(
      "merged_from_schedule_id" => existing_schedule["schedule_id"],
      "start_date" => merged_days.first&.fetch("date"),
      "program_length_days" => merged_days.length,
      "days" => merged_days
    )
  end

  def write_schedule(schedule, schedule_key)
    schedule_output_dir.mkpath
    path = schedule_output_dir.join(schedule_filename(schedule_key))
    path.write(JSON.pretty_generate(schedule) + "\n")
    path
  end

  def write_feeds(schedule)
    feed_output_dir.mkpath
    base_path = feed_output_dir.join(feed_basename)
    feed = FeedWriter.new(
      schedule:,
      calendar_name: feed_title
    ).build
    ics_path = base_path.sub_ext(".ics")
    webcal_path = base_path.sub_ext(".webcal")
    ics_path.write(feed)
    webcal_path.write(feed)
    {ics: ics_path, webcal: webcal_path}
  end

  def schedule_filename(schedule_key)
    "schedule-#{schedule_key}.json"
  end

  def feed_basename
    feed_output_basename || "schedule"
  end

  def schedule_context(schedule, limit_days: 28)
    days = schedule.fetch("days")
    recent_days = days.last(limit_days)

    recent_days.map do |day|
      pieces = [day.fetch("date")]
      pieces << ((day["day_type"] == "workout") ? day.fetch("workout").fetch("title") : "Rest")
      pieces << day["notes"] if day["notes"] && !day["notes"].to_s.empty?
      pieces.join(" | ")
    end.join("\n")
  end
end
