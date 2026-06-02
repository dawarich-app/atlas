require "rails_helper"

RSpec.describe BeaconEvent, type: :model do
  describe "associations" do
    it { expect(described_class.reflect_on_association(:project).macro).to eq :belongs_to }
  end

  describe "validations" do
    subject(:event) { build(:beacon_event) }

    it { is_expected.to be_valid }

    it "requires an origin" do
      event.origin = nil
      expect(event).not_to be_valid
    end

    it "requires a version" do
      event.version = nil
      expect(event).not_to be_valid
    end

    it "rejects origin longer than 200 chars" do
      event.origin = "https://" + ("a" * 200)
      expect(event).not_to be_valid
    end

    it "rejects version longer than 100 chars" do
      event.version = "v" + ("0" * 100)
      expect(event).not_to be_valid
    end
  end

  describe ".active_origins_within" do
    let(:project) { create(:project) }

    it "returns distinct origins seen within the window" do
      Timecop.freeze(Time.current) do
        create(:beacon_event, project: project, origin: "https://a.example",  created_at: 5.days.ago)
        create(:beacon_event, project: project, origin: "https://a.example",  created_at: 2.days.ago) # dup
        create(:beacon_event, project: project, origin: "https://b.example",  created_at: 10.days.ago)
        create(:beacon_event, project: project, origin: "https://c.example",  created_at: 40.days.ago) # outside
        result = described_class.active_origins_within(project, 30.days)
        expect(result).to contain_exactly("https://a.example", "https://b.example")
      end
    end
  end
end
