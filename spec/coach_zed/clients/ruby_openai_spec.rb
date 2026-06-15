# frozen_string_literal: true

RSpec.describe CoachZed::Clients::RubyOpenAI do
  it "extracts the returned message content from a ruby-openai style response" do
    client = instance_double("RubyOpenAIClient")
    response = {
      "choices" => [
        {
          "message" => {
            "content" => "{\"program_length_days\":1,\"days\":[{\"day_number\":1,\"day_type\":\"rest\",\"workout\":null,\"notes\":\"Rest.\"}]}"
          }
        }
      ]
    }

    expect(client).to receive(:chat).with(parameters: hash_including(:model, :messages)).and_return(response)

    content = described_class.new(client: client).generate(prompt: "Build a schedule.")

    expect(content).to include("\"program_length_days\":1")
  end
end
