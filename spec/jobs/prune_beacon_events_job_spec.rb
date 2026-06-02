require "rails_helper"

RSpec.describe PruneBeaconEventsJob, type: :job do
  it "deletes beacon events older than 90 days" do
    project = create(:project)
    Timecop.freeze(Time.current) do
      old1 = create(:beacon_event, project: project, origin: "https://a", created_at: 100.days.ago)
      old2 = create(:beacon_event, project: project, origin: "https://b", created_at: 91.days.ago)
      kept1 = create(:beacon_event, project: project, origin: "https://c", created_at: 89.days.ago)
      kept2 = create(:beacon_event, project: project, origin: "https://d", created_at: 1.day.ago)

      expect { described_class.perform_now }
        .to change(BeaconEvent, :count).by(-2)

      expect(BeaconEvent.where(id: [kept1.id, kept2.id])).to have_attributes(count: 2)
      expect(BeaconEvent.where(id: [old1.id, old2.id])).to be_empty
    end
  end

  it "is a no-op when nothing is old enough" do
    create(:beacon_event, created_at: 1.day.ago)
    expect { described_class.perform_now }.not_to change(BeaconEvent, :count)
  end
end
