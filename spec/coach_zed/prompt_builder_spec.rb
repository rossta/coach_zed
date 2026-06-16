# frozen_string_literal: true

require "date"

RSpec.describe CoachZed::PromptBuilder do
  let(:catalog) do
    [
      CoachZed::Catalog::Entry.new(
        path: Pathname("/tmp/workouts/bodyweight/push-up-emom-10-min.md"),
        relative_path: "bodyweight/push-up-emom-10-min.md",
        title: "Push Up EMOM 10 Min",
        domain: "bodyweight",
        session_duration: "10 min",
        frequency: "2-4x/week",
        program: nil,
        format: "EMOM",
        equipment: "none",
        summary: "Progressive push-up EMOM.",
        work_items: ["Pick a push-up number."],
        notes: ["Increase reps over time."],
        source_urls: []
      )
    ]
  end

  it "builds a JSON-only scheduling prompt" do
    prompt = described_class.new(
      consultation_prompt: "For the next month, improve push-up volume.",
      catalog: catalog,
      start_date: Date.new(2026, 6, 15),
      schedule_key: "abc123",
      generation_days: 28,
      existing_feed_context: "2026-06-08 | Existing workout"
    ).build

    expect(prompt).to include("Return strict JSON only")
    expect(prompt).to include("For the next month, improve push-up volume.")
    expect(prompt).to include("Push Up EMOM 10 Min")
    expect(prompt).to include("Start date: 2026-06-15")
    expect(prompt).to include("program_length_days")
    expect(prompt).to include("Produce exactly 28 entries")
    expect(prompt).to include("Existing feed context")
    expect(prompt).to include("Required JSON Schema")
  end
end
