# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "yaml"
require "tmpdir"

RSpec.describe FitnessButler do
  let(:catalog_dir) { File.expand_path("../../fitness_calendar/workouts", __dir__) }
  let(:consultation_prompt) { "For the next month, improve swing speed while keeping recovery manageable." }
  let(:start_date) { Date.new(2026, 6, 15) }
  let(:schedule_response) do
    {
      "program_name" => "Swing Speed Month",
      "program_length_days" => 3,
      "days" => [
        {
          "day_number" => 1,
          "day_type" => "workout",
          "workout" => {
            "title" => "Push Up EMOM 10 Min",
            "catalog_path" => "bodyweight/push-up-emom-10-min.md",
            "domain" => "bodyweight",
            "session_duration" => "10 min"
          },
          "notes" => "Build consistency."
        },
        {
          "day_number" => 2,
          "day_type" => "rest",
          "workout" => nil,
          "notes" => "Recovery day."
        },
        {
          "day_number" => 3,
          "day_type" => "workout",
          "workout" => {
            "title" => "Suitcase Carry",
            "catalog_path" => "kettlebells/suitcase-carry.md",
            "domain" => "kettlebells",
            "session_duration" => "~20-25 min"
          },
          "notes" => "Carry day."
        }
      ]
    }.to_json
  end

  let(:weekly_schedule_response) do
    {
      "program_name" => "Swing Speed Week",
      "program_length_days" => 7,
      "days" => Array.new(7) do |index|
        day_type = if index == 6
          "rest"
        else
          "workout"
        end

        workout = if index == 6
          nil
        else
          {
            "title" => "Push Up EMOM 10 Min",
            "catalog_path" => "bodyweight/push-up-emom-10-min.md",
            "domain" => "bodyweight",
            "session_duration" => "10 min"
          }
        end

        {
          "day_number" => index + 1,
          "day_type" => day_type,
          "workout" => workout,
          "notes" => "Week #{index + 1}."
        }
      end
    }.to_json
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  def openai_client_with(response)
    prompts = []
    client = OpenAI::Client.new(access_token: "test-token")
    allow(client).to receive(:chat) do |parameters:|
      prompts << parameters.fetch(:messages).first.fetch(:content)
      response
    end
    [client, prompts]
  end

  it "generates schedule json and calendar feeds" do
    client, prompts = openai_client_with(
      "choices" => [
        {
          "message" => {
            "content" => schedule_response
          }
        }
      ]
    )
    coach = described_class.new(
      workout_catalog_dir: catalog_dir,
      client: client,
      output_dir: File.join(@tmpdir, "results"),
      feed_output_basename: "current"
    )

    result = coach.generate_schedule(
      consultation_prompt: consultation_prompt,
      start_date: start_date
    )

    schedule = JSON.parse(File.read(result.schedule_path))

    expect(prompts.first).to include(consultation_prompt)
    expect(prompts.first).to include("Push Up EMOM 10 Min")
    expect(schedule["start_date"]).to eq("2026-06-15")
    expect(schedule["days"].length).to eq(3)
    expect(File).to exist(result.ics_path)
    expect(File).to exist(result.webcal_path)
    expect(result.ics_path.basename.to_s).to eq("current.ics")
    expect(result.webcal_path.basename.to_s).to eq("current.webcal")
    expect(File.read(result.ics_path)).to include("BEGIN:VCALENDAR")
    expect(File.read(result.ics_path)).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(File.read(result.ics_path)).to include("SUMMARY:Rest")
  end

  it "accepts a consultation prompt file path and overwrites existing feeds" do
    prompt_path = File.join(@tmpdir, "consultation.txt")
    File.write(prompt_path, consultation_prompt)

    first_client = openai_client_with(
      "choices" => [
        {
          "message" => {
            "content" => schedule_response
          }
        }
      ]
    ).first
    coach = described_class.new(
      workout_catalog_dir: catalog_dir,
      client: first_client,
      output_dir: File.join(@tmpdir, "results"),
      feed_output_basename: "current"
    )

    first_result = coach.generate_schedule(
      consultation_prompt_path: prompt_path,
      start_date: start_date
    )

    File.write(first_result.ics_path, "stale")
    File.write(first_result.webcal_path, "stale")

    second_schedule_response = JSON.parse(schedule_response)
    second_schedule_response["days"][0]["notes"] = "Updated plan."
    second_client = openai_client_with(
      "choices" => [
        {
          "message" => {
            "content" => second_schedule_response.to_json
          }
        }
      ]
    ).first
    second_coach = described_class.new(
      workout_catalog_dir: catalog_dir,
      client: second_client,
      output_dir: File.join(@tmpdir, "results"),
      feed_output_basename: "current"
    )

    second_result = second_coach.generate_schedule(
      consultation_prompt_path: prompt_path,
      start_date: start_date
    )

    expect(second_result.schedule_path).to eq(first_result.schedule_path)
    expect(File.read(second_result.ics_path)).not_to eq("stale")
    expect(File.read(second_result.webcal_path)).to eq(File.read(second_result.ics_path))
    expect(JSON.parse(File.read(second_result.schedule_path))["days"][0]["notes"]).to eq("Updated plan.")
  end

  it "appends to an existing feed and starts after the current end date" do
    existing_feed_path = File.join(@tmpdir, "feeds", "current.ics")
    FileUtils.mkdir_p(File.dirname(existing_feed_path))
    File.write(
      existing_feed_path,
      <<~ICAL
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//FitnessButler//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        X-WR-CALNAME:Current Plan
        X-WR-TIMEZONE:America/New_York
        BEGIN:VEVENT
        UID:existing-1@fitness_butler
        DTSTAMP:20260601T120000Z
        DTSTART;VALUE=DATE:20260615
        DTEND;VALUE=DATE:20260616
        SUMMARY:Existing Workout
        DESCRIPTION:Prior week.
        END:VEVENT
        BEGIN:VEVENT
        UID:existing-2@fitness_butler
        DTSTAMP:20260601T120000Z
        DTSTART;VALUE=DATE:20260621
        DTEND;VALUE=DATE:20260622
        SUMMARY:Existing Rest
        DESCRIPTION:Prior week.
        END:VEVENT
        END:VCALENDAR
      ICAL
    )

    client = openai_client_with(
      "choices" => [
        {
          "message" => {
            "content" => weekly_schedule_response
          }
        }
      ]
    ).first
    coach = described_class.new(
      workout_catalog_dir: catalog_dir,
      client: client,
      output_dir: File.join(@tmpdir, "results"),
      feed_output_basename: "current",
      existing_feed_path: existing_feed_path
    )

    result = coach.generate_schedule(
      consultation_prompt: consultation_prompt,
      start_date: Date.new(2026, 6, 15)
    )

    schedule = JSON.parse(File.read(result.schedule_path))

    expect(schedule["start_date"]).to eq("2026-06-22")
    expect(schedule["program_length_days"]).to eq(7)
    expect(File.read(result.ics_path)).to include("SUMMARY:Existing Workout")
    expect(File.read(result.ics_path)).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(File.read(result.ics_path)).to include("DTSTART;VALUE=DATE:20260622")
  end

  it "validates prompt source arguments" do
    client = openai_client_with(
      "choices" => [
        {
          "message" => {
            "content" => schedule_response
          }
        }
      ]
    ).first
    coach = described_class.new(
      workout_catalog_dir: catalog_dir,
      client: client,
      output_dir: File.join(@tmpdir, "results")
    )

    expect do
      coach.generate_schedule(start_date: start_date)
    end.to raise_error(ArgumentError)
  end

  it "raises for unsupported clients during initialization" do
    expect do
      described_class.new(
        workout_catalog_dir: catalog_dir,
        client: Object.new
      )
    end.to raise_error(ArgumentError, /unsupported client/i)
  end

  it "loads config from a local .fitness_butler.yml file" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, ".fitness_butler.yml")
      File.write(
        config_path,
        {
          "workout_catalog_dir" => catalog_dir,
          "output_dir" => File.join(dir, "results"),
          "feed_output_basename" => "current"
        }.to_yaml
      )

      client = openai_client_with(
        "choices" => [
          {
            "message" => {
              "content" => schedule_response
            }
          }
        ]
      ).first

      Dir.chdir(dir) do
        coach = described_class.new(client: client)
        result = coach.generate_schedule(
          consultation_prompt: consultation_prompt,
          start_date: start_date
        )

        expect(result.ics_path.basename.to_s).to eq("current.ics")
        expect(File).to exist(result.schedule_path)
      end
    end
  end

  it "loads config from ~/.config/fitness_butler.yml when local config is absent" do
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, ".config")
      FileUtils.mkdir_p(config_dir)
      File.write(
        File.join(config_dir, "fitness_butler.yml"),
        {
          "workout_catalog_dir" => catalog_dir,
          "output_dir" => File.join(dir, "results"),
          "feed_output_basename" => "current"
        }.to_yaml
      )

      client = openai_client_with(
        "choices" => [
          {
            "message" => {
              "content" => schedule_response
            }
          }
        ]
      ).first

      original_home = ENV["HOME"]
      ENV["HOME"] = dir
      begin
        coach = described_class.new(client: client)
        result = coach.generate_schedule(
          consultation_prompt: consultation_prompt,
          start_date: start_date
        )

        expect(result.webcal_path.basename.to_s).to eq("current.webcal")
      ensure
        ENV["HOME"] = original_home
      end
    end
  end
end
