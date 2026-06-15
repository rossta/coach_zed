# frozen_string_literal: true

require "date"
require "time"

class CoachZed
  class FeedWriter
    def initialize(schedule:, start_date:, existing_feed_content: nil)
      @schedule = schedule
      @start_date = start_date
      @existing_feed_content = existing_feed_content
    end

    def build
      if existing_feed_content
        append_to_existing_feed(existing_feed_content)
      else
        fresh_feed
      end
    end

    private

    attr_reader :schedule, :start_date, :existing_feed_content

    def fresh_feed
      lines = header_lines
      lines.concat(event_lines)
      lines << "END:VCALENDAR"
      lines.join("\r\n") + "\r\n"
    end

    def append_to_existing_feed(existing_feed)
      event_block = event_lines.join("\r\n") + "\r\n"
      existing_feed.sub(/END:VCALENDAR\s*\z/, "#{event_block}END:VCALENDAR\r\n")
    end

    def header_lines
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//CoachZed//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:#{escape(schedule_name)}",
        "X-WR-TIMEZONE:America/New_York"
      ]
    end

    def event_lines
      schedule.fetch("days").flat_map do |day|
        date = start_date + (day.fetch("day_number").to_i - 1)
        [
          "BEGIN:VEVENT",
          "UID:#{schedule.fetch("schedule_id")}-#{format("%02d", day.fetch("day_number").to_i)}@coach_zed",
          "DTSTAMP:#{generated_timestamp}",
          "DTSTART;VALUE=DATE:#{date.strftime("%Y%m%d")}",
          "DTEND;VALUE=DATE:#{(date + 1).strftime("%Y%m%d")}",
          "SUMMARY:#{escape(event_summary(day))}",
          "DESCRIPTION:#{escape(event_description(day))}",
          "END:VEVENT"
        ]
      end
    end

    def schedule_name
      schedule["program_name"] || "Training Schedule"
    end

    def generated_timestamp
      Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    end

    def event_summary(day)
      return "Rest" if day["day_type"] == "rest"

      day.fetch("workout").fetch("title")
    end

    def event_description(day)
      pieces = []
      pieces << day["notes"].to_s if day["notes"] && !day["notes"].to_s.empty?
      if day["day_type"] == "workout"
        workout = day.fetch("workout")
        pieces << "Catalog path: #{workout.fetch("catalog_path")}"
        pieces << "Domain: #{workout.fetch("domain")}"
        pieces << "Session duration: #{workout.fetch("session_duration")}"
      end
      pieces.join("\n")
    end

    def escape(value)
      value.to_s
        .gsub("\\", "\\\\")
        .gsub(";", "\\;")
        .gsub(",", "\\,")
        .gsub("\r\n", "\\n")
        .gsub("\n", "\\n")
    end
  end
end
