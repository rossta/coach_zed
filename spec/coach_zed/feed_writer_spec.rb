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
    expect(feed).to include("X-WR-CALNAME:Test Plan")
    expect(feed).to include("SUMMARY:Push Up EMOM 10 Min")
    expect(feed).to include("SUMMARY:Rest")
    expect(feed).to include("DTSTART;VALUE=DATE:20260615")
    expect(feed).to include("DTSTART;VALUE=DATE:20260616")
    expect(feed).to include("Progressive push-up EMOM built around a sustainable rep target")
    expect(feed).not_to include("Catalog path:")
  end

  it "appends new events to an existing feed without rewriting old content" do
    existing_feed = <<~ICAL
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//CoachZed//EN
      CALSCALE:GREGORIAN
      METHOD:PUBLISH
      X-WR-CALNAME:Test Plan
      X-WR-TIMEZONE:America/New_York
      BEGIN:VEVENT
      UID:existing-1@coach_zed
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

  it "replaces overlapping existing events when appending" do
    existing_feed = <<~ICAL
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//CoachZed//EN
      CALSCALE:GREGORIAN
      METHOD:PUBLISH
      X-WR-CALNAME:Test Plan
      X-WR-TIMEZONE:America/New_York
      BEGIN:VEVENT
      UID:existing-1@coach_zed
      DTSTAMP:20260601T120000Z
      DTSTART;VALUE=DATE:20260621
      DTEND;VALUE=DATE:20260622
      SUMMARY:Existing Workout
      DESCRIPTION:Prior week.
      END:VEVENT
      BEGIN:VEVENT
      UID:existing-2@coach_zed
      DTSTAMP:20260601T120000Z
      DTSTART;VALUE=DATE:20260622
      DTEND;VALUE=DATE:20260623
      SUMMARY:Overlapping Workout
      DESCRIPTION:Should be replaced.
      END:VEVENT
      BEGIN:VEVENT
      UID:existing-3@coach_zed
      DTSTAMP:20260601T120000Z
      DTSTART;VALUE=DATE:20260623
      DTEND;VALUE=DATE:20260624
      SUMMARY:Another Overlap
      DESCRIPTION:Should also be replaced.
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
    expect(feed).not_to include("SUMMARY:Overlapping Workout")
    expect(feed).not_to include("SUMMARY:Another Overlap")
    expect(feed.scan("BEGIN:VEVENT").length).to eq(3)
    expect(feed.scan("DTSTART;VALUE=DATE:20260621").length).to eq(1)
    expect(feed.scan("DTSTART;VALUE=DATE:20260622").length).to eq(1)
    expect(feed.scan("DTSTART;VALUE=DATE:20260623").length).to eq(1)
  end

  it "uses a configured calendar title when provided" do
    feed = described_class.new(
      schedule:,
      start_date: Date.new(2026, 6, 15),
      calendar_name: "Morning Training"
    ).build

    expect(feed).to include("X-WR-CALNAME:Morning Training")
  end
end
