# frozen_string_literal: true

require "date"

RSpec.describe CoachZed::FeedWriter do
  let(:schedule) do
    {
      "schedule_id" => "abc123",
      "program_name" => "Test Plan",
      "days" => [
        {
          "day_number" => 1,
          "date" => "2026-06-15",
          "day_type" => "workout",
          "workout" => {
            "title" => "Push Up EMOM 10 Min",
            "catalog_path" => "bodyweight/push-up-emom-10-min.md",
            "domain" => "bodyweight",
            "session_duration" => "10 min",
            "catalog_text" => <<~TEXT
              # Push Up EMOM 10 Min

              - Domain: `bodyweight`
              - Session Duration: `10 min`

              ## Summary

              Progressive push-up EMOM built around a sustainable rep target that you can repeat every minute for 10 minutes.
            TEXT
          },
          "notes" => "Build consistency."
        },
        {
          "day_number" => 2,
          "date" => "2026-06-16",
          "day_type" => "rest",
          "workout" => nil,
          "notes" => "Recovery."
        }
      ]
    }
  end

  it "renders a calendar feed with daily events" do
    feed = described_class.new(schedule:).build

    expect(feed).to include("BEGIN:VCALENDAR")
    expect(feed).to include("X-WR-CALNAME:Test Plan")
    expect(feed).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(feed).to include("SUMMARY:Rest")
    expect(feed).to include("DTSTART;VALUE=DATE:20260615")
    expect(feed).to include("DTSTART;VALUE=DATE:20260616")
    expect(feed).to include("Progressive push-up EMOM built around a sustainable rep target")
    expect(feed).not_to include("Catalog path:")
  end

  it "uses stable date-based identifiers" do
    feed = described_class.new(schedule:).build

    expect(feed).to include("UID:20260615@coach_zed")
    expect(feed).to include("UID:20260616@coach_zed")
    expect(feed).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(feed.scan("BEGIN:VEVENT").length).to eq(2)
  end

  it "uses a configured calendar title when provided" do
    feed = described_class.new(schedule:, calendar_name: "Morning Training").build

    expect(feed).to include("X-WR-CALNAME:Morning Training")
  end
end
