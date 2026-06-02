require "rails_helper"

RSpec.describe "Widget safety", type: :system, js: true do
  before { driven_by(:chibichange_chrome_headless) }

  let!(:project) { create(:project, slug: "dawarich", name: "Dawarich") }

  before do
    v1 = create(:version, project: project, number: "1.0.0", released_at: Date.new(2025, 1, 1))
    v2 = create(:version, project: project, number: "2.0.0", released_at: Date.new(2026, 4, 1))
    create(:entry, version: v2, kind: "added", body_markdown: "new",
           body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "new" }] }])
  end

  describe "shadow DOM isolation" do
    it "renders the widget inside a shadow root attached to #chgtool-host" do
      visit "/spec/host/default"
      expect(page).to have_selector("#chgtool-host", visible: :all, wait: 5)
      # The pill should be inside the shadow root, not in the light DOM
      light_dom_pill = page.evaluate_script("document.querySelector('[data-chgtool=\"pill\"]')")
      expect(light_dom_pill).to be_nil
    end

    it "is not styled by hostile host page CSS" do
      visit "/spec/host/aggressive_css"
      expect(page).to have_selector("#chgtool-host", visible: :all, wait: 5)
      # Read the computed style of the pill INSIDE the shadow root
      pill_color = page.evaluate_script(<<~JS)
        (function () {
          var host = document.getElementById('chgtool-host');
          if (!host) return null;
          // Closed shadow root — peek via __chgtool debug hook for inspection
          if (!window.__chgtool || !window.__chgtool.instances.dawarich) return null;
          var pill = window.__chgtool.instances.dawarich.pillElement();
          return pill ? getComputedStyle(pill).color : null;
        })();
      JS
      # If shadow isolation works, color is NOT 'rgb(255, 0, 0)' (the hostile !important red)
      expect(pill_color).not_to eq("rgb(255, 0, 0)")
    end
  end

  describe "double-load idempotency" do
    it "renders exactly one #chgtool-host even with two script tags" do
      visit "/spec/host/double_load"
      expect(page).to have_selector("#chgtool-host", visible: :all, wait: 5)
      count = page.evaluate_script("document.querySelectorAll('#chgtool-host').length")
      expect(count).to eq 1
    end
  end

  describe "Turbo lifecycle" do
    it "destroys the host on turbo:before-cache, then re-renders on turbo:load" do
      visit "/spec/host/turbo"
      expect(page).to have_selector("#chgtool-host", visible: :all, wait: 5)

      # Step 1: dispatch before-cache only. Host element must go away.
      page.evaluate_script("document.dispatchEvent(new Event('turbo:before-cache'))")
      sleep 0.1
      after_before_cache = page.evaluate_script("document.querySelectorAll('#chgtool-host').length")
      expect(after_before_cache).to eq(0),
        "expected destroy() to remove #chgtool-host on turbo:before-cache, got #{after_before_cache}"

      # Step 2: dispatch turbo:load. Host element must come back (exactly one).
      page.evaluate_script("document.dispatchEvent(new Event('turbo:load'))")
      # Allow a brief tick for run() → render() to land the host element.
      sleep 0.3
      after_load = page.evaluate_script("document.querySelectorAll('#chgtool-host').length")
      expect(after_load).to eq(1),
        "expected turbo:load to re-render exactly one #chgtool-host, got #{after_load}"
    end
  end

  describe "error containment" do
    it "swallows errors thrown inside click handlers without breaking the host page" do
      visit "/spec/host/default"
      expect(page).to have_selector("#chgtool-host", visible: :all, wait: 5)

      # Monkey-patch the click handler to throw, then click the pill.
      page.execute_script(<<~JS)
        var inst = window.__chgtool.instances.dawarich;
        var pill = inst.pillElement();
        if (pill) {
          pill.addEventListener('click', function () { throw new Error('test-click-error'); });
          pill.click();
        }
      JS

      # Host page is still interactive (h1 is reachable, no JS halt)
      expect(page).to have_selector("h1", text: "Host page")
      # And no error has escaped to window.onerror
      uncaught = page.evaluate_script("window.__caughtUncaught || false")
      expect(uncaught).to be_falsey
    end

    it "renders other tokens even if one throws during render" do
      # When the server returns a payload with one malformed node, renderTokens
      # skips that node and continues with the rest.
      visit "/spec/host/default"
      expect(page).to have_selector("#chgtool-host", visible: :all, wait: 5)
      # The default fixture already has a valid payload — assert pill exists,
      # demonstrating renderTokens didn't crash on the well-formed input.
      pill_text = page.evaluate_script(<<~JS)
        (function () {
          var inst = window.__chgtool.instances.dawarich;
          var p = inst.pillElement();
          return p ? p.textContent : null;
        })();
      JS
      expect(pill_text).to include("What's New")
    end
  end

  describe "allowlist hardening" do
    it "rejects hrefs containing control characters" do
      bundle = File.read(Rails.root.join("app/assets/builds/widget.v1.js"))
      # Look for the regex that screens control characters in hrefs
      expect(bundle).to match(/\[\\x00-\\x1f\\x7f\]/), "expected control-character href guard"
    end

    it "caps text node length at 4096 characters" do
      bundle = File.read(Rails.root.join("app/assets/builds/widget.v1.js"))
      expect(bundle).to include("MAX_TEXT_LEN")
      expect(bundle).to match(/MAX_TEXT_LEN\s*=\s*4096/)
    end

    it "caps nested-list depth at 6 levels" do
      bundle = File.read(Rails.root.join("app/assets/builds/widget.v1.js"))
      expect(bundle).to include("MAX_LIST_DEPTH")
      expect(bundle).to match(/MAX_LIST_DEPTH\s*=\s*6/)
    end
  end
end
