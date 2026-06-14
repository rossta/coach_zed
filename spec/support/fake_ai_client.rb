# frozen_string_literal: true

class FakeAiClient
  attr_reader :prompts

  def initialize(responses)
    @responses = Array(responses).dup
    @prompts = []
  end

  def generate(prompt:)
    prompts << prompt
    responses.shift
  end

  private

  attr_reader :responses
end
