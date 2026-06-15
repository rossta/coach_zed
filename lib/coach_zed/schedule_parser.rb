# frozen_string_literal: true

require "json"

class CoachZed
  class ScheduleParser
    class Error < StandardError; end

    def self.parse(raw_schedule)
      json = extract_json(raw_schedule)
      schedule = JSON.parse(json)
      validate!(schedule)
      schedule
    rescue JSON::ParserError => e
      raise Error, "invalid schedule JSON: #{e.message}"
    end

    def self.extract_json(raw_schedule)
      text = raw_schedule.to_s.strip
      return text unless text.start_with?("```")

      fenced = text.match(/```(?:json)?\s*(.*?)\s*```/m)
      fenced ? fenced[1].to_s.strip : text
    end

    def self.validate!(schedule)
      raise Error, "schedule must be a JSON object" unless schedule.is_a?(Hash)

      days = schedule.fetch("days")
      raise Error, "schedule must contain days" unless days.is_a?(Array) && !days.empty?

      expected_length = schedule["program_length_days"] || days.length
      raise Error, "program_length_days must match days length" unless expected_length.to_i == days.length

      days.each_with_index do |day, index|
        validate_day!(day, index + 1)
      end
    rescue KeyError => e
      raise Error, "missing required schedule field: #{e.key}"
    end

    def self.validate_day!(day, expected_day_number)
      raise Error, "each day must be an object" unless day.is_a?(Hash)
      raise Error, "day_number must be sequential" unless day.fetch("day_number").to_i == expected_day_number
      raise Error, "day_type must be workout or rest" unless %w[workout rest].include?(day.fetch("day_type"))
      raise Error, "notes must be present" unless day.key?("notes")

      if day["day_type"] == "workout"
        workout = day.fetch("workout")
        raise Error, "workout must be present for workout days" unless workout.is_a?(Hash)

        %w[title catalog_path domain session_duration].each do |field|
          raise Error, "workout must include #{field}" unless workout[field].is_a?(String) && !workout[field].empty?
        end
      end
    rescue KeyError => e
      raise Error, "missing required day field: #{e.key}"
    end
  end
end
