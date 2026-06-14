# frozen_string_literal: true

require "date"

RSpec.describe FitnessButler::FeedWriter do
  let(:schedule) do
    {
      "schedule_id" => "abc123",
      "program_name" => "Test Plan",
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
          "notes" => "Recovery."
        }
      ]
    }
  end

  it "renders a calendar feed with daily events" do
    feed = described_class.new(schedule:, start_date: Date.new(2026, 6, 15)).build

    expect(feed).to include("BEGIN:VCALENDAR")
    expect(feed).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(feed).to include("SUMMARY:Rest")
    expect(feed).to include("DTSTART;VALUE=DATE:20260615")
    expect(feed).to include("DTSTART;VALUE=DATE:20260616")
    expect(feed).to include("Catalog path: bodyweight/push-up-emom-10-min.md")
  end

  it "appends new events to an existing feed without rewriting old content" do
    existing_feed = <<~ICAL
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//FitnessButler//EN
      CALSCALE:GREGORIAN
      METHOD:PUBLISH
      X-WR-CALNAME:Test Plan
      X-WR-TIMEZONE:America/New_York
      BEGIN:VEVENT
      UID:existing-1@fitness_butler
      DTSTAMP:20260601T120000Z
      DTSTART;VALUE=DATE:20260615
      DTEND;VALUE=DATE:20260616
      SUMMARY:Existing Workout
      DESCRIPTION:Prior week.
      END:VEVENT
      END:VCALENDAR
    ICAL

    feed = described_class.new(
      schedule:,
      start_date: Date.new(2026, 6, 22),
      existing_feed_content: existing_feed
    ).build

    expect(feed).to include("SUMMARY:Existing Workout")
    expect(feed).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(feed.scan("BEGIN:VEVENT").length).to eq(3)
  end
end
