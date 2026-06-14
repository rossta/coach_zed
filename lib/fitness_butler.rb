# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "pathname"

require_relative "fitness_butler/version"
require_relative "fitness_butler/catalog"
require_relative "fitness_butler/clients/ruby_openai"
require_relative "fitness_butler/feed_reader"
require_relative "fitness_butler/feed_writer"
require_relative "fitness_butler/prompt_builder"
require_relative "fitness_butler/schedule_parser"

class FitnessButler
  Result = Struct.new(:schedule_path, :ics_path, :webcal_path, :schedule, keyword_init: true)

  def initialize(
    workout_catalog_dir:,
    client:,
    model: "gpt-4.1",
    schedule_output_dir: "schedules",
    feed_output_dir: "feeds",
    feed_output_basename: nil,
    existing_feed_path: nil
  )
    @workout_catalog_dir = Pathname(workout_catalog_dir)
    @ai_client = wrap_client(client, model:)
    @schedule_output_dir = Pathname(schedule_output_dir)
    @feed_output_dir = Pathname(feed_output_dir)
    @feed_output_basename = feed_output_basename
    @existing_feed_path = existing_feed_path && Pathname(existing_feed_path)
  end

  def generate_schedule(start_date:, consultation_prompt: nil, consultation_prompt_path: nil)
    prompt_text = resolve_prompt_text(consultation_prompt, consultation_prompt_path)
    catalog = Catalog::Loader.new(@workout_catalog_dir).load
    existing_feed = load_existing_feed
    start_date = generation_start_date(start_date, existing_feed:)
    generation_days = existing_feed ? 7 : 28
    existing_feed_context = existing_feed&.to_context(limit_days: 28)
    schedule_key = schedule_key_for(prompt_text, start_date, catalog, generation_days, existing_feed_context)
    prompt = PromptBuilder.new(
      consultation_prompt: prompt_text,
      catalog: catalog,
      start_date: start_date,
      schedule_key: schedule_key,
      generation_days: generation_days,
      existing_feed_context: existing_feed_context
    ).build
    raw_schedule = @ai_client.generate(prompt:)
    schedule = ScheduleParser.parse(raw_schedule)
    schedule = normalize_schedule(schedule, start_date:, prompt_text:, schedule_key:, catalog:, generation_days:)

    schedule_path = write_schedule(schedule, schedule_key)
    feed_paths = write_feeds(schedule, start_date:, schedule_key:, existing_feed:)

    Result.new(
      schedule_path: schedule_path,
      ics_path: feed_paths.fetch(:ics),
      webcal_path: feed_paths.fetch(:webcal),
      schedule: schedule
    )
  end

  private

  attr_reader :workout_catalog_dir, :ai_client, :schedule_output_dir, :feed_output_dir, :feed_output_basename, :existing_feed_path

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

    Pathname(consultation_prompt_path).read
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

  def generation_start_date(start_date, existing_feed:)
    return normalize_date(start_date) if existing_feed.nil? || existing_feed.last_date.nil?

    existing_feed.last_date + 1
  end

  def schedule_key_for(prompt_text, start_date, catalog, generation_days, existing_feed_context)
    Digest::SHA256.hexdigest(
      [
        prompt_text.strip,
        start_date.iso8601,
        generation_days,
        catalog_digest(catalog),
        existing_feed_context.to_s
      ].join("\n")
    )[0, 12]
  end

  def catalog_digest(catalog)
    Digest::SHA256.hexdigest(catalog.map(&:fingerprint).join("\n"))
  end

  def normalize_schedule(schedule, start_date:, prompt_text:, schedule_key:, catalog:, generation_days:)
    days = schedule.fetch("days")
    normalized_days = days.each_with_index.map do |day, index|
      day_number = day.fetch("day_number", index + 1).to_i
      date = start_date + (day_number - 1)
      workout = day["workout"]
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
      "days" => normalized_days
    )
  end

  def write_schedule(schedule, schedule_key)
    schedule_output_dir.mkpath
    path = schedule_output_dir.join(schedule_filename(schedule_key))
    path.write(JSON.pretty_generate(schedule) + "\n")
    path
  end

  def write_feeds(schedule, start_date:, schedule_key:, existing_feed:)
    feed_output_dir.mkpath
    base_path = feed_output_dir.join(feed_basename(schedule_key))
    feed = FeedWriter.new(
      schedule:,
      start_date:,
      existing_feed_content: existing_feed&.feed_content
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

  def feed_basename(schedule_key)
    feed_output_basename || "schedule-#{schedule_key}"
  end
end
