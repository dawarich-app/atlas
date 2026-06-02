require "rails_helper"

RSpec.describe WidgetPayload do
  let(:project) { create(:project, slug: "dawarich", name: "Dawarich") }

  # Pull the rendered text content out of the new versions structure.
  def all_entry_text(payload)
    Array(payload[:versions]).flat_map do |v|
      v[:entries_by_kind].values.flat_map do |tokens|
        tokens.flat_map { |t| Array(t["c"]).map { |c| c["v"] }.compact }
      end
    end
  end

  let!(:v1) do
    create(:version, project: project, number: "1.0.0", released_at: Date.new(2025, 1, 1)).tap do |v|
      create(:entry, version: v, kind: "added", body_markdown: "first",
             body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "first" }] }])
    end
  end

  let!(:v2) do
    create(:version, project: project, number: "2.0.0", released_at: Date.new(2026, 4, 1)).tap do |v|
      create(:entry, version: v, kind: "added", body_markdown: "second",
             body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "second" }] }])
      create(:entry, version: v, kind: "fixed", body_markdown: "bug",
             body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "bug" }] }])
    end
  end

  describe ".call" do
    it "returns project meta" do
      payload = described_class.call(project: project, requested_version: "1.0.0")
      expect(payload[:project]).to eq(slug: "dawarich", name: "Dawarich")
    end

    it "returns latest_version and latest_released_at" do
      payload = described_class.call(project: project, requested_version: "1.0.0")
      expect(payload[:latest_version]).to eq "2.0.0"
      expect(payload[:latest_released_at]).to eq "2026-04-01"
    end

    it "returns entries from versions strictly newer than the requested version" do
      payload = described_class.call(project: project, requested_version: "1.0.0")
      expect(all_entry_text(payload)).to include("second", "bug")
      expect(all_entry_text(payload)).not_to include("first")
    end

    it "groups entries by version + kind in Keep-a-Changelog order" do
      payload = described_class.call(project: project, requested_version: "1.0.0")
      versions = payload[:versions]
      expect(versions.length).to eq 1
      expect(versions.first).to include(number: "2.0.0", released_at: "2026-04-01")
      # 2.0.0 has one added + one fixed entry — Added must precede Fixed.
      expect(versions.first[:entries_by_kind].keys).to eq %w[added fixed]
    end

    it "returns counts by kind aggregated across shown versions" do
      payload = described_class.call(project: project, requested_version: "1.0.0")
      expect(payload[:counts]).to eq("added" => 1, "fixed" => 1)
      expect(payload[:total_entries]).to eq 2
    end

    it "marks update_available true when requested is older than latest" do
      payload = described_class.call(project: project, requested_version: "1.0.0")
      expect(payload[:update_available]).to be true
    end

    it "marks update_available false when requested matches latest" do
      payload = described_class.call(project: project, requested_version: "2.0.0")
      expect(payload[:update_available]).to be false
    end

    it "marks update_available nil when requested doesn't match any released version" do
      payload = described_class.call(project: project, requested_version: "deadbeef")
      expect(payload[:update_available]).to be_nil
      # Returns ALL released entries when version is unknown (not just "since latest")
      expect(all_entry_text(payload)).to include("first", "second", "bug")
    end

    it "ignores yanked versions when computing latest" do
      yk = create(:version, :yanked, project: project, number: "3.0.0", released_at: Date.new(2026, 5, 1))
      create(:entry, version: yk, kind: "added", body_markdown: "yanked thing",
             body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "yanked thing" }] }])

      payload = described_class.call(project: project, requested_version: "1.0.0")
      expect(payload[:latest_version]).to eq "2.0.0"
      expect(all_entry_text(payload)).not_to include("yanked thing")
    end

    it "skips Unreleased version" do
      create(:version, :unreleased, project: project)
      payload = described_class.call(project: project, requested_version: "1.0.0")
      expect(payload[:latest_version]).to eq "2.0.0"
    end

    it "returns empty versions when no released versions exist" do
      empty_proj = create(:project)
      create(:version, :unreleased, project: empty_proj)
      payload = described_class.call(project: empty_proj, requested_version: "1.0.0")
      expect(payload[:latest_version]).to be_nil
      expect(payload[:versions]).to eq []
      expect(payload[:counts]).to eq({})
      expect(payload[:total_entries]).to eq 0
      expect(payload[:update_available]).to be_nil
    end

    context "with more than MAX_VERSIONS_SHOWN newer versions" do
      let(:big_project) { create(:project, slug: "lots", name: "Lots") }

      before do
        # 5 newer versions on top of the baseline 1.0.0 + 2.0.0 the let blocks
        # above seeded on `project`. We use a fresh project to keep numbers tidy.
        create(:version, project: big_project, number: "1.0.0", released_at: Date.new(2025, 1, 1)).tap do |v|
          create(:entry, version: v, kind: "added", body_markdown: "v1",
                 body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "v1 entry" }] }])
        end
        5.times do |i|
          create(:version, project: big_project, number: "2.#{i}.0", released_at: Date.new(2026, i + 1, 1)).tap do |v|
            create(:entry, version: v, kind: "added", body_markdown: "v2.#{i}",
                   body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "v2.#{i} entry" }] }])
          end
        end
      end

      it "caps the versions array to the top 3 versions" do
        payload = described_class.call(project: big_project, requested_version: "1.0.0")
        # 5 newer versions exist; top 3 by release date are 2.4.0, 2.3.0, 2.2.0
        expect(payload[:versions].map { |v| v[:number] }).to eq %w[2.4.0 2.3.0 2.2.0]
        expect(all_entry_text(payload)).to contain_exactly("v2.4 entry", "v2.3 entry", "v2.2 entry")
        expect(all_entry_text(payload)).not_to include("v2.1 entry", "v2.0 entry", "v1 entry")
      end

      it "exposes the overflow as more_versions_count" do
        payload = described_class.call(project: big_project, requested_version: "1.0.0")
        expect(payload[:more_versions_count]).to eq 2  # 5 newer − 3 shown
      end

      it "reports zero overflow when total newer ≤ cap" do
        payload = described_class.call(project: project, requested_version: "1.0.0")
        # `project` (the outer let) has just one newer version (2.0.0).
        expect(payload[:more_versions_count]).to eq 0
      end
    end
  end
end
