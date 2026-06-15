# frozen_string_literal: true

class CoachZed
  module Clients
    class RubyOpenAI
      def initialize(client:, model: "gpt-4.1")
        @client = client
        @model = model
      end

      def generate(prompt:)
        response = client.chat(parameters: {
          model: model,
          messages: [{role: "user", content: prompt}]
        })
        extract_content(response)
      end

      private

      attr_reader :client, :model

      def extract_content(response)
        return response if response.is_a?(String)

        if response.respond_to?(:dig)
          content = response.dig("choices", 0, "message", "content") ||
            response.dig(:choices, 0, :message, :content)
          return content if content.is_a?(String)
        end

        if response.respond_to?(:[])
          content = response["choices"]&.first&.dig("message", "content") ||
            response[:choices]&.first&.dig(:message, :content)
          return content if content.is_a?(String)
        end

        raise ArgumentError, "unable to extract content from ruby-openai response"
      end
    end
  end
end
