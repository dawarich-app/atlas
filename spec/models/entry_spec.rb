require "rails_helper"

RSpec.describe Entry, type: :model do
  describe "associations" do
    it { expect(described_class.reflect_on_association(:version).macro).to eq :belongs_to }
  end

  describe "validations" do
    subject(:entry) { build(:entry) }

    it { is_expected.to be_valid }

    it "requires a kind" do
      entry.kind = nil
      expect(entry).not_to be_valid
    end

    it "rejects unknown kinds" do
      expect { entry.kind = "feature" }.to raise_error(ArgumentError)
    end

    it "accepts the six Keep a Changelog kinds" do
      %w[added changed deprecated removed fixed security].each do |k|
        e = build(:entry, kind: k)
        expect(e).to be_valid, "expected #{k.inspect} to be valid"
      end
    end

    it "requires body_markdown" do
      entry.body_markdown = nil
      expect(entry).not_to be_valid
    end
  end

  describe ".ordered" do
    let(:version) { create(:version) }

    it "orders by position asc, created_at asc as tiebreaker" do
      c = create(:entry, version: version, position: 2)
      a = create(:entry, version: version, position: 0)
      b = create(:entry, version: version, position: 1)
      expect(version.entries.ordered.to_a).to eq [a, b, c]
    end
  end

  describe ".by_kind" do
    let(:version) { create(:version) }

    it "groups entries by kind preserving Keep a Changelog order" do
      create(:entry, version: version, kind: "fixed",   position: 0)
      create(:entry, version: version, kind: "added",   position: 1)
      create(:entry, version: version, kind: "added",   position: 2)
      create(:entry, version: version, kind: "security", position: 3)

      grouped = version.entries.by_kind
      expect(grouped.keys).to eq %w[added fixed security]
      expect(grouped["added"].count).to eq 2
    end
  end
end
