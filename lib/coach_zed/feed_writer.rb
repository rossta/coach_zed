# frozen_string_literal: true

require "date"
require "time"

class CoachZed
  class FeedWriter
    def initialize(schedule:, calendar_name: nil)
      @schedule = schedule
      @calendar_name = calendar_name
    end

    def build
      fresh_feed
    end

    private

    attr_reader :schedule, :calendar_name

    def fresh_feed
      lines = header_lines
      lines.concat(event_lines)
      lines << "END:VCALENDAR"
      lines.join("\r\n") + "\r\n"
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
        date = Date.strptime(day.fetch("date"), "%Y-%m-%d")
        [
          "BEGIN:VEVENT",
          "UID:#{date.strftime("%Y%m%d")}@coach_zed",
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
      calendar_name || schedule["program_name"] || "Training Schedule"
    end

    def generated_timestamp
      Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    end

    def event_summary(day)
      return "Rest" if day["day_type"] == "rest"

      day.fetch("workout").fetch("title")
    end

    def event_description(day)
      # @type var pieces: Array[String]
      pieces = []
      pieces << day["notes"].to_s if day["notes"] && !day["notes"].to_s.empty?
      if day["day_type"] == "workout"
        workout = day.fetch("workout")
        catalog_text = workout["catalog_text"].to_s
        pieces << catalog_text unless catalog_text.empty?
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
