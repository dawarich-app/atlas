require "rails_helper"

RSpec.describe "Widget on a host page", type: :system, js: true do
  before { driven_by(:chibichange_chrome_headless) }

  let!(:project) { create(:project, slug: "dawarich", name: "Dawarich") }

  before do
    v1 = create(:version, project: project, number: "1.0.0", released_at: Date.new(2025, 1, 1))
    v2 = create(:version, project: project, number: "2.0.0", released_at: Date.new(2026, 4, 1))
    create(:entry, version: v1, kind: "added", body_markdown: "first",
           body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "first" }] }])
    create(:entry, version: v2, kind: "added", body_markdown: "second",
           body_tokens: [{ "t" => "p", "c" => [{ "t" => "text", "v" => "second" }] }])
  end

  it "renders the pill, opens the modal, records a beacon" do
    expect {
      visit "/spec/host/default"
      # The widget renders inside a closed shadow root, so query via the debug hook.
      expect(page).to have_selector("#chgtool-host", visible: :all, wait: 5)
      Timeout.timeout(5) do
        loop do
          ready = page.evaluate_script(
            "!!(window.__chgtool && window.__chgtool.instances && window.__chgtool.instances.dawarich && window.__chgtool.instances.dawarich.pillElement())"
          )
          break if ready
          sleep 0.1
        end
      end
    }.to change(BeaconEvent, :count).by(1)

    event = BeaconEvent.last
    expect(event.version).to eq "1.0.0"
    expect(event.origin).to be_present

    pill_text = page.evaluate_script(<<~JS)
      (function () {
        var pill = window.__chgtool.instances.dawarich.pillElement();
        return pill ? pill.textContent : null;
      })();
    JS
    expect(pill_text).to include("What's New")
    expect(pill_text).to include("(1)")  # one entry newer than 1.0.0

    # Click the pill inside the shadow root and inspect the resulting modal.
    page.execute_script("window.__chgtool.instances.dawarich.pillElement().click();")

    modal_text = Timeout.timeout(5) do
      result = nil
      loop do
        result = page.evaluate_script(<<~JS)
          (function () {
            var pill = window.__chgtool.instances.dawarich.pillElement();
            if (!pill) return null;
            var root = pill.getRootNode();
            var modal = root.querySelector('[data-chgtool="modal"]');
            return modal ? modal.textContent : null;
          })();
        JS
        break result if result
        sleep 0.1
      end
    end

    expect(modal_text).to include("Dawarich")
    expect(modal_text).to include("second")
    expect(modal_text).to include("Update available")
  end

  it "mounts the host inside a data-mount target instead of the body" do
    visit "/spec/host/mounted"

    expect(page).to have_selector("#chgtool-host", visible: :all, wait: 5)
    Timeout.timeout(5) do
      loop do
        ready = page.evaluate_script(
          "!!(window.__chgtool && window.__chgtool.instances && window.__chgtool.instances.dawarich && window.__chgtool.instances.dawarich.pillElement())"
        )
        break if ready
        sleep 0.1
      end
    end

    parent_id = page.evaluate_script(<<~JS)
      (function () {
        var host = document.getElementById('chgtool-host');
        return host && host.parentNode ? host.parentNode.id : null;
      })();
    JS
    expect(parent_id).to eq "version-mount"

    pill_class = page.evaluate_script(
      "window.__chgtool.instances.dawarich.pillElement().className"
    )
    expect(pill_class).to include "chgtool-pill--inline"

    # Inline pill is a pure visual indicator — pulsing green dot, no text.
    pill_text = page.evaluate_script(
      "window.__chgtool.instances.dawarich.pillElement().textContent"
    )
    expect(pill_text).to eq ""
    aria = page.evaluate_script(
      "window.__chgtool.instances.dawarich.pillElement().getAttribute('aria-label')"
    )
    expect(aria).to eq "Show changelog"

    # When the inline pill is clicked, the modal must be hoisted to a separate
    # host on document.body so its position:fixed/inset:0 escapes any
    # transformed/contained ancestor the mount target lives under.
    page.execute_script("window.__chgtool.instances.dawarich.pillElement().click();")

    modal_host_parent = Timeout.timeout(5) do
      result = nil
      loop do
        result = page.evaluate_script(<<~JS)
          (function () {
            var mh = document.getElementById('chgtool-host-modal');
            return mh ? mh.parentNode.tagName : null;
          })();
        JS
        break result if result
        sleep 0.1
      end
    end
    expect(modal_host_parent).to eq "BODY"
  end

  describe "consent gate" do
    it "renders nothing and records no beacon when data-consent=declined" do
      expect {
        visit "/spec/host/declined"
        sleep 0.5
      }.not_to change(BeaconEvent, :count)

      mounted = page.evaluate_script(
        "!!(window.__chgtool && window.__chgtool.instances && window.__chgtool.instances.dawarich)"
      )
      expect(mounted).to be false
      expect(page).not_to have_selector("#chgtool-host", visible: :all)
    end
  end

  describe "seen state" do
    it "writes a fingerprint to localStorage when the pill is clicked" do
      visit "/spec/host/default"

      Timeout.timeout(5) do
        loop do
          ready = page.evaluate_script(
            "!!(window.__chgtool && window.__chgtool.instances && window.__chgtool.instances.dawarich && window.__chgtool.instances.dawarich.pillElement())"
          )
          break if ready
          sleep 0.1
        end
      end

      page.execute_script("window.__chgtool.instances.dawarich.pillElement().click();")

      seen = Timeout.timeout(5) do
        result = nil
        loop do
          result = page.evaluate_script("localStorage.getItem('chgtool:seen:dawarich')")
          break result if result
          sleep 0.1
        end
      end
      expect(seen).to eq "2.0.0|2026-04-01"
    end

    it "suppresses the floating pill entirely when the stored fingerprint matches" do
      # Floating mode is intrusive on its own — once acknowledged, hide it.
      visit "/spec/host/default"
      page.execute_script("localStorage.setItem('chgtool:seen:dawarich', '2.0.0|2026-04-01')")
      visit "/spec/host/default"

      sleep 0.5
      mounted = page.evaluate_script(
        "!!(window.__chgtool && window.__chgtool.instances && window.__chgtool.instances.dawarich && window.__chgtool.instances.dawarich.pillElement())"
      )
      expect(mounted).to be false
    end

    it "keeps the inline dot visible but static when the fingerprint matches" do
      # Inline mode stays visible after read — a deliberate UX choice: the dot is
      # an ambient indicator that an update exists, but with no pulse and
      # reduced opacity so it doesn't beg for attention again.
      visit "/spec/host/mounted"
      page.execute_script("localStorage.setItem('chgtool:seen:dawarich', '2.0.0|2026-04-01')")
      visit "/spec/host/mounted"

      Timeout.timeout(5) do
        loop do
          ready = page.evaluate_script(
            "!!(window.__chgtool && window.__chgtool.instances && window.__chgtool.instances.dawarich && window.__chgtool.instances.dawarich.pillElement())"
          )
          break if ready
          sleep 0.1
        end
      end

      pill_class = page.evaluate_script(
        "window.__chgtool.instances.dawarich.pillElement().className"
      )
      expect(pill_class).to include "chgtool-pill--inline"
      expect(pill_class).to include "chgtool-pill--seen"
    end
  end
end
