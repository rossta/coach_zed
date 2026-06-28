# frozen_string_literal: true

require "date"
require "time"

class CoachZed
  class FeedWriter
    def initialize(schedule:, start_date:, existing_feed_content: nil, calendar_name: nil)
      @schedule = schedule
      @start_date = start_date
      @existing_feed_content = existing_feed_content
      @calendar_name = calendar_name
    end

    def build
      if existing_feed_content
        append_to_existing_feed(existing_feed_content)
      else
        fresh_feed
      end
    end

    private

    attr_reader :schedule, :start_date, :existing_feed_content, :calendar_name

    def fresh_feed
      lines = header_lines
      lines.concat(event_lines)
      lines << "END:VCALENDAR"
      lines.join("\r\n") + "\r\n"
    end

    def append_to_existing_feed(existing_feed)
      prefix, existing_blocks = split_existing_feed(existing_feed)
      kept_blocks = existing_blocks.filter { |block| existing_event_date(block).nil? || existing_event_date(block) < start_date }
      event_block = event_lines.join("\r\n") + "\r\n"
      "#{prefix}#{kept_blocks.join}#{event_block}END:VCALENDAR\r\n"
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

    def split_existing_feed(existing_feed)
      match = existing_feed.match(/\A(?<prefix>.*?)(?<events>(?:BEGIN:VEVENT\r?\n.*?END:VEVENT\r?\n?)*)END:VCALENDAR\s*\z/m)
      return [existing_feed.sub(/END:VCALENDAR\s*\z/, ""), []] if match.nil?

      [
        match[:prefix],
        match[:events].scan(/BEGIN:VEVENT\r?\n.*?END:VEVENT\r?\n?/m)
      ]
    end

    def existing_event_date(event_block)
      match = event_block.match(/^DTSTART;VALUE=DATE:(\d{8})$/m)
      return if match.nil?

      Date.strptime(match[1], "%Y%m%d")
    end
  end
end
