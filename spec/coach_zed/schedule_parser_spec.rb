# frozen_string_literal: true

require "json"

RSpec.describe CoachZed::ScheduleParser do
  it "parses valid schedule JSON" do
    payload = {
      "program_name" => "Test Plan",
      "program_length_days" => 2,
      "days" => [
        {
          "day_number" => 1,
          "day_type" => "workout",
          "workout" => {
            "title" => "Suitcase Carry",
            "catalog_path" => "kettlebells/suitcase-carry.md",
            "domain" => "kettlebells",
            "session_duration" => "~20-25 min"
          },
          "notes" => "Carry."
        },
        {
          "day_number" => 2,
          "day_type" => "rest",
          "workout" => nil,
          "notes" => "Rest."
        }
      ]
    }.to_json

    schedule = described_class.parse(payload)

    expect(schedule["days"].length).to eq(2)
    expect(schedule["days"].last["day_type"]).to eq("rest")
  end

  it "accepts fenced JSON responses" do
    payload = <<~JSON
      ```json
      {"program_length_days":1,"days":[{"day_number":1,"day_type":"rest","workout":null,"notes":"Rest."}]}
      ```
    JSON

    schedule = described_class.parse(payload)
    expect(schedule["days"].first["day_type"]).to eq("rest")
  end

  it "normalizes program_length_days to match days" do
    payload = {
      "program_name" => "Mismatch Plan",
      "program_length_days" => 99,
      "days" => [
        {
          "day_number" => 1,
          "day_type" => "rest",
          "workout" => nil,
          "notes" => "Rest."
        },
        {
          "day_number" => 2,
          "day_type" => "rest",
          "workout" => nil,
          "notes" => "Rest again."
        }
      ]
    }.to_json

    schedule = described_class.parse(payload)

    expect(schedule["program_length_days"]).to eq(2)
  end
end
