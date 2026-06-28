# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "yaml"
require "tmpdir"

RSpec.describe CoachZed do
  let(:catalog_dir) { File.expand_path("fixtures/workouts", __dir__) }
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

  def schedule_fixture(payload, start_date:, schedule_id: "existing-schedule")
    schedule = JSON.parse(payload)
    schedule["schedule_id"] = schedule_id
    schedule["start_date"] = start_date.iso8601
    schedule["days"].each_with_index do |day, index|
      day["date"] = (start_date + index).iso8601
    end
    schedule
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
    expect(schedule["merge_policy"]).to eq("replace")
    expect(schedule["days"].length).to eq(3)
    expect(schedule["days"].first["workout"]["catalog_text"]).to include("# Push Up EMOM 10 Min")
    expect(File).to exist(result.ics_path)
    expect(File).to exist(result.webcal_path)
    expect(result.ics_path.basename.to_s).to eq("current.ics")
    expect(result.webcal_path.basename.to_s).to eq("current.webcal")
    expect(File.read(result.ics_path)).to include("BEGIN:VCALENDAR")
    expect(File.read(result.ics_path)).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(File.read(result.ics_path)).to include("Progressive push-up EMOM built around a sustainable rep target")
    expect(File.read(result.ics_path)).to include("SUMMARY:Rest")
  end

  it "defaults feed basenames to schedule when unset" do
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

    result = coach.generate_schedule(
      consultation_prompt: consultation_prompt,
      start_date: start_date
    )

    expect(result.ics_path.basename.to_s).to eq("schedule.ics")
    expect(result.webcal_path.basename.to_s).to eq("schedule.webcal")
  end

  it "uses a configured feed title for new feeds" do
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
      output_dir: File.join(@tmpdir, "results"),
      feed_output_basename: "current",
      feed_title: "Ross Training Plan"
    )

    result = coach.generate_schedule(
      consultation_prompt: consultation_prompt,
      start_date: start_date
    )

    expect(File.read(result.ics_path)).to include("X-WR-CALNAME:Ross Training Plan")
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

  it "appends to an existing schedule json and renders a merged feed" do
    existing_schedule_path = File.join(@tmpdir, "schedules", "current.json")
    FileUtils.mkdir_p(File.dirname(existing_schedule_path))
    File.write(
      existing_schedule_path,
      JSON.pretty_generate(schedule_fixture(weekly_schedule_response, start_date: Date.new(2026, 6, 15), schedule_id: "existing-week")) + "\n"
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
      existing_schedule_path: existing_schedule_path
    )

    result = coach.generate_schedule(
      consultation_prompt: consultation_prompt,
      start_date: Date.new(2026, 6, 15),
      generation_mode: :append,
      merge_policy: :append
    )

    schedule = JSON.parse(File.read(result.schedule_path))

    expect(schedule["merge_policy"]).to eq("append")
    expect(schedule["merged_from_schedule_id"]).to eq("existing-week")
    expect(schedule["start_date"]).to eq("2026-06-15")
    expect(schedule["program_length_days"]).to eq(14)
    expect(schedule["days"].first["date"]).to eq("2026-06-15")
    expect(schedule["days"][7]["date"]).to eq("2026-06-22")
    expect(schedule["days"][7]["workout"]["catalog_text"]).to include("# Push Up EMOM 10 Min")
    expect(File.read(result.ics_path)).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(File.read(result.ics_path)).to include("Progressive push-up EMOM built around a sustainable rep target")
    expect(File.read(result.ics_path)).to include("DTSTART;VALUE=DATE:20260615")
    expect(File.read(result.ics_path)).to include("DTSTART;VALUE=DATE:20260628")
  end

  it "replaces the current period on pushes and ignores an existing schedule json" do
    existing_schedule_path = File.join(@tmpdir, "schedules", "current.json")
    FileUtils.mkdir_p(File.dirname(existing_schedule_path))
    File.write(
      existing_schedule_path,
      JSON.pretty_generate(schedule_fixture(weekly_schedule_response, start_date: Date.new(2026, 5, 18), schedule_id: "existing-week")) + "\n"
    )

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
      feed_output_basename: "current",
      existing_schedule_path: existing_schedule_path
    )

    result = coach.generate_schedule(
      consultation_prompt: consultation_prompt,
      start_date: start_date,
      generation_mode: :refresh,
      merge_policy: :replace
    )

    schedule = JSON.parse(File.read(result.schedule_path))

    expect(prompts.first).to include("Produce exactly 35 entries")
    expect(prompts.first).to include("Existing feed context (most recent weeks, if available):")
    expect(prompts.first).to include("none")
    expect(schedule["start_date"]).to eq("2026-06-15")
    expect(schedule["merge_policy"]).to eq("replace")
    expect(schedule["days"].first["workout"]["catalog_text"]).to include("# Push Up EMOM 10 Min")
    expect(File.read(result.ics_path)).to include("SUMMARY:Push Up EMOM 10 Min")
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

  it "loads config from a local .coach_zed.yml file" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, ".coach_zed.yml")
      File.write(
        config_path,
        {
          "workout_catalog_dir" => catalog_dir,
          "output_dir" => File.join(dir, "results"),
          "feed_output_basename" => "current",
          "feed_title" => "Configured Plan"
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
        expect(File.read(result.ics_path)).to include("X-WR-CALNAME:Configured Plan")
      end
    end
  end

  it "loads config from ~/.config/coach_zed.yml when local config is absent" do
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, ".config")
      FileUtils.mkdir_p(config_dir)
      File.write(
        File.join(config_dir, "coach_zed.yml"),
        {
          "workout_catalog_dir" => catalog_dir,
          "output_dir" => File.join(dir, "results"),
          "feed_output_basename" => "current",
          "feed_title" => "Home Configured Plan"
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
        expect(File.read(result.ics_path)).to include("X-WR-CALNAME:Home Configured Plan")
      ensure
        ENV["HOME"] = original_home
      end
    end
  end
end
