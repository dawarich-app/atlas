require "rails_helper"

RSpec.describe InstanceMetrics do
  let(:project) { create(:project) }

  describe ".for" do
    it "returns zeros when there are no beacons" do
      m = described_class.for(project)
      expect(m.active_30d).to eq 0
      expect(m.version_distribution_30d).to eq []
      expect(m.daily_30d).to eq []
    end

    it "counts distinct origins seen in the last 30 days" do
      Timecop.freeze(Time.current) do
        create(:beacon_event, project: project, origin: "https://a.example", version: "1.0", created_at: 1.day.ago)
        create(:beacon_event, project: project, origin: "https://a.example", version: "1.0", created_at: 2.days.ago) # dup
        create(:beacon_event, project: project, origin: "https://b.example", version: "1.0", created_at: 5.days.ago)
        create(:beacon_event, project: project, origin: "https://c.example", version: "1.0", created_at: 40.days.ago) # outside

        m = described_class.for(project)
        expect(m.active_30d).to eq 2
      end
    end

    it "groups distinct origins by version (most recent version wins per origin)" do
      Timecop.freeze(Time.current) do
        # Origin "a" upgraded from 1.0 to 2.0 — should count as 2.0 only
        create(:beacon_event, project: project, origin: "https://a.example", version: "1.0", created_at: 10.days.ago)
        create(:beacon_event, project: project, origin: "https://a.example", version: "2.0", created_at: 1.day.ago)
        # Origin "b" still on 1.0
        create(:beacon_event, project: project, origin: "https://b.example", version: "1.0", created_at: 3.days.ago)

        dist = described_class.for(project).version_distribution_30d
        expect(dist).to contain_exactly(
          { version: "2.0", count: 1 },
          { version: "1.0", count: 1 }
        )
      end
    end

    it "produces a daily count series for the last 30 days" do
      Timecop.freeze(Time.zone.local(2026, 4, 30)) do
        create(:beacon_event, project: project, origin: "https://a.example", version: "1", created_at: Time.zone.local(2026, 4, 29))
        create(:beacon_event, project: project, origin: "https://b.example", version: "1", created_at: Time.zone.local(2026, 4, 29))
        create(:beacon_event, project: project, origin: "https://a.example", version: "1", created_at: Time.zone.local(2026, 4, 28))

        daily = described_class.for(project).daily_30d
        expect(daily.size).to eq 30
        d29 = daily.find { |row| row[:date] == Date.new(2026, 4, 29) }
        d28 = daily.find { |row| row[:date] == Date.new(2026, 4, 28) }
        expect(d29[:active]).to eq 2
        expect(d28[:active]).to eq 1
      end
    end
  end
end
