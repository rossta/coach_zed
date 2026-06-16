# frozen_string_literal: true

class CoachZed
  module ScheduleSchema
    module_function

    def to_h
      {
        type: "object",
        properties: {
          program_name: {type: "string"},
          program_length_days: {type: "integer"},
          days: {
            type: "array",
            items: {
              type: "object",
              properties: {
                day_number: {type: "integer"},
                day_type: {
                  type: "string",
                  enum: %w[workout rest]
                },
                workout: {
                  anyOf: [
                    {
                      type: "object",
                      properties: {
                        title: {type: "string"},
                        catalog_path: {type: "string"},
                        domain: {type: "string"},
                        session_duration: {type: "string"}
                      },
                      required: %w[title catalog_path domain session_duration],
                      additionalProperties: false
                    },
                    {type: "null"}
                  ]
                },
                notes: {type: "string"}
              },
              required: %w[day_number day_type workout notes],
              additionalProperties: false
            }
          }
        },
        required: %w[program_name program_length_days days],
        additionalProperties: false
      }
    end
  end
end
