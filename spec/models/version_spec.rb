require "rails_helper"

RSpec.describe Version, type: :model do
  describe "associations" do
    it { expect(described_class.reflect_on_association(:project).macro).to eq :belongs_to }
    it do
      assoc = described_class.reflect_on_association(:entries)
      expect(assoc.macro).to eq :has_many
      expect(assoc.options[:dependent]).to eq :destroy
    end
  end

  describe "validations" do
    subject(:version) { build(:version) }

    it { is_expected.to be_valid }

    it "requires a number" do
      version.number = nil
      expect(version).not_to be_valid
    end

    it "rejects duplicate (project, number)" do
      first = create(:version, number: "1.0.0")
      duplicate = build(:version, project: first.project, number: "1.0.0")
      expect(duplicate).not_to be_valid
    end

    it "allows the same number across different projects" do
      a = create(:version, number: "1.0.0")
      b = build(:version, number: "1.0.0", project: create(:project))
      expect(b).to be_valid
    end

    it "yanked defaults to false" do
      expect(create(:version).yanked).to eq false
    end
  end

  describe "#unreleased?" do
    it "is true when released_at is nil" do
      expect(build(:version, released_at: nil).unreleased?).to be true
    end

    it "is false when released_at is set" do
      expect(build(:version, released_at: Date.today).unreleased?).to be false
    end
  end

  describe ".ordered" do
    let(:project) { create(:project) }

    it "puts the unreleased version on top, then released by date desc" do
      old      = create(:version, project: project, number: "1.0.0", released_at: Date.new(2024, 1, 1))
      newer    = create(:version, project: project, number: "2.0.0", released_at: Date.new(2025, 6, 1))
      unreleased = create(:version, project: project, number: "Unreleased", released_at: nil)

      expect(project.versions.ordered.to_a).to eq [unreleased, newer, old]
    end
  end

  describe ".unreleased_for" do
    let(:project) { create(:project) }

    it "returns the project's open Unreleased version" do
      unreleased = create(:version, project: project, number: "Unreleased", released_at: nil)
      create(:version, project: project, number: "1.0.0", released_at: Date.today)
      expect(Version.unreleased_for(project)).to eq unreleased
    end

    it "returns nil if no Unreleased exists" do
      create(:version, project: project, number: "1.0.0", released_at: Date.today)
      expect(Version.unreleased_for(project)).to be_nil
    end
  end

  describe "#release!" do
    let(:project) { create(:project) }
    let!(:version) { create(:version, project: project, number: "Unreleased", released_at: nil) }

    it "sets number and released_at" do
      version.release!(number: "1.2.0", released_at: Date.new(2026, 4, 30))
      expect(version.reload).to have_attributes(number: "1.2.0", released_at: Date.new(2026, 4, 30))
    end

    it "raises if already released" do
      version.release!(number: "1.0.0", released_at: Date.today)
      expect { version.release!(number: "1.1.0", released_at: Date.today) }
        .to raise_error(Version::AlreadyReleased)
    end
  end

  describe "#yank!" do
    it "flips yanked to true" do
      v = create(:version, number: "1.0.0", released_at: Date.today)
      expect { v.yank! }.to change { v.reload.yanked }.from(false).to(true)
    end

    it "is a no-op on an unreleased version" do
      v = create(:version, number: "Unreleased", released_at: nil)
      expect { v.yank! }.to raise_error(Version::CannotYankUnreleased)
    end
  end
end
