# frozen_string_literal: true

require "json"

class CoachZed
  class PromptBuilder
    def initialize(consultation_prompt:, catalog:, start_date:, schedule_key:, generation_days:, existing_feed_context: nil)
      @consultation_prompt = consultation_prompt
      @catalog = catalog
      @start_date = start_date
      @schedule_key = schedule_key
      @generation_days = generation_days
      @existing_feed_context = existing_feed_context
    end

    def build
      <<~PROMPT
        You are a training coach. Build a daily training schedule for the athlete using only the provided catalog.

        Return JSON only. Do not wrap it in markdown fences or commentary.

        Required schema:
        {
          "program_name": string,
          "program_length_days": integer,
          "days": [
            {
              "day_number": integer,
              "day_type": "workout" or "rest",
              "workout": {
                "title": string,
                "catalog_path": string,
                "domain": string,
                "session_duration": string
              } or null,
              "notes": string
            }
          ]
        }

        Rules:
        - Produce exactly #{generation_days} entries for the requested time period.
        - Include rest days when appropriate.
        - Use only workouts that exist in the catalog.
        - Match the athlete's goals and the requested time period.
        - If existing feed context is provided, continue from the end of the prior feed and avoid changing earlier weeks.
        - Keep the JSON valid and complete.

        Schedule metadata:
        - Start date: #{@start_date.iso8601}
        - Schedule key: #{@schedule_key}

        Athlete consultation prompt:
        #{@consultation_prompt}

        Existing feed context (most recent weeks, if available):
        #{existing_feed_context || "none"}

        Catalog:
        #{JSON.pretty_generate(catalog.map(&:to_h))}
      PROMPT
    end

    private

    attr_reader :consultation_prompt, :catalog, :start_date, :schedule_key, :generation_days, :existing_feed_context
  end
end
