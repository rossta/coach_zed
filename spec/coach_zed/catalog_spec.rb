# frozen_string_literal: true

require "pathname"

RSpec.describe CoachZed::Catalog::Loader do
  let(:catalog_dir) { File.expand_path("../../../fitness_calendar/workouts", __dir__) }

  it "loads catalog entries and ignores template files" do
    entries = described_class.new(catalog_dir).load

    expect(entries.map(&:relative_path)).to include("swing-speed/the-stack-foundation.md")
    expect(entries.map(&:relative_path)).to include("kettlebells/suitcase-carry.md")
    expect(entries.map(&:relative_path)).not_to include("INDEX.md")
    expect(entries.map(&:relative_path)).not_to include("TEMPLATE.md")
    expect(entries.find { |entry| entry.title == "The Stack: Foundation" }.program).to eq("18 sessions total, ~6 weeks")
  end
end
