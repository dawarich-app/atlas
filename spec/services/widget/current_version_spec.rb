require "rails_helper"

RSpec.describe Widget::CurrentVersion do
  describe ".value" do
    it "returns a semver-shaped string" do
      expect(described_class.value).to match(/\A\d+\.\d+\.\d+\z/)
    end

    it "is frozen (can't be mutated by callers)" do
      expect(described_class.value).to be_frozen
    end
  end

  describe ".immutable_path_segment" do
    it "returns the version prefixed for the loader path" do
      expect(described_class.immutable_path_segment).to eq "v#{described_class.value}"
    end
  end
end
