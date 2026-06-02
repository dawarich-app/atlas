require "rails_helper"

RSpec.describe Project, type: :model do
  describe "associations" do
    it "belongs to a user" do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq :belongs_to
    end

    it "has many versions, dependent destroy" do
      assoc = described_class.reflect_on_association(:versions)
      expect(assoc.macro).to eq :has_many
      expect(assoc.options[:dependent]).to eq :destroy
    end
  end

  describe "validations" do
    subject(:project) { build(:project) }

    it { is_expected.to be_valid }

    it "requires a name" do
      project.name = nil
      expect(project).not_to be_valid
    end

    it "requires a slug" do
      project.slug = nil
      expect(project).not_to be_valid
    end

    it "rejects slugs shorter than 3 chars" do
      project.slug = "ab"
      expect(project).not_to be_valid
    end

    it "rejects slugs longer than 63 chars" do
      project.slug = "a" * 64
      expect(project).not_to be_valid
    end

    it "rejects slugs with uppercase letters" do
      project.slug = "MyProject"
      expect(project).not_to be_valid
    end

    it "rejects slugs that start with a hyphen" do
      project.slug = "-foo"
      expect(project).not_to be_valid
    end

    it "rejects slugs that end with a hyphen" do
      project.slug = "foo-"
      expect(project).not_to be_valid
    end

    it "accepts slugs with internal hyphens" do
      project.slug = "my-cool-app-2"
      expect(project).to be_valid
    end

    it "rejects duplicate slugs case-insensitively" do
      create(:project, slug: "dawarich")
      duplicate = build(:project, slug: "DAWARICH")
      duplicate.valid?
      expect(duplicate.errors[:slug]).to include(/taken/i)
    end
  end

  describe "#to_param" do
    it "returns the slug" do
      project = build(:project, slug: "dawarich")
      expect(project.to_param).to eq "dawarich"
    end
  end
end
