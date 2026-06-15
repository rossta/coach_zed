# frozen_string_literal: true

require "date"

class CoachZed
  class FeedReader
    class Event
      attr_reader :date, :summary, :description

      def initialize(date: nil, summary: nil, description: nil)
        @date = date
        @summary = summary
        @description = description
      end
    end

    def self.load(path)
      new(File.read(path.to_s)).events
    end

    def self.load_existing(path)
      new(File.read(path.to_s))
    end

    def initialize(feed_content)
      @feed_content = feed_content
    end

    attr_reader :feed_content

    def events
      @events ||= parse_events
    end

    def last_date
      events.map(&:date).compact.max
    end

    def recent_events(limit_days: 28)
      last = last_date
      cutoff = last ? last - (limit_days - 1) : nil
      return events if cutoff.nil?

      events.select { |event| event.date && event.date >= cutoff }
    end

    def to_context(limit_days: 28)
      recent_events(limit_days:).map do |event|
        # @type var pieces: Array[String]
        pieces = []
        pieces << event.date.iso8601 if event.date
        pieces << event.summary if event.summary && !event.summary.empty?
        pieces << event.description if event.description && !event.description.empty?
        pieces.join(" | ")
      end.join("\n")
    end

    private

    def parse_events
      blocks = feed_content.split(/BEGIN:VEVENT\r?\n/).drop(1)
      blocks.filter_map do |block|
        event_text = block.split("END:VEVENT").first
        next if event_text.nil?

        Event.new(
          date: parse_date(event_text),
          summary: parse_line(event_text, /^SUMMARY:(.*)$/),
          description: unescape(parse_line(event_text, /^DESCRIPTION:(.*)$/))
        )
      end
    end

    def parse_date(event_text)
      value = parse_line(event_text, /^DTSTART;VALUE=DATE:(\d{8})$/)
      return if value.nil?

      Date.strptime(value, "%Y%m%d")
    end

    def parse_line(event_text, pattern)
      match = event_text.match(pattern)
      match && match[1]
    end

    def unescape(value)
      value.to_s
        .gsub("\\n", "\n")
        .gsub("\\,", ",")
        .gsub("\\;", ";")
        .gsub("\\\\", "\\")
    end
  end
end
