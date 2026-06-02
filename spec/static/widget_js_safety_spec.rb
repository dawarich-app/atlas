require "rails_helper"

RSpec.describe "Widget JS safety invariants", type: :static do
  let(:bundle_path) { Rails.root.join("app/assets/builds/widget.v1.js") }
  let(:source)      { File.read(bundle_path) }

  it "never uses innerHTML / outerHTML / document.write" do
    expect(source).not_to match(/\binnerHTML\b/), "innerHTML usage found in widget.v1.js"
    expect(source).not_to match(/\bouterHTML\b/), "outerHTML usage found in widget.v1.js"
    expect(source).not_to match(/\bdocument\.write\b/), "document.write usage found in widget.v1.js"
  end

  it "never uses eval or new Function" do
    expect(source).not_to match(/\beval\s*\(/), "eval() usage found in widget.v1.js"
    expect(source).not_to match(/\bnew\s+Function\b/), "new Function usage found in widget.v1.js"
  end

  it "never binds window.onerror or document-level error listeners" do
    expect(source).not_to match(/window\.onerror\s*=/), "window.onerror assignment found"
    expect(source).not_to match(/addEventListener\(\s*['"]error['"]/), "global error listener found"
  end

  it "embeds the current widget version" do
    expect(source).to include(%Q(var WIDGET_VERSION = "#{Widget::CurrentVersion.value}"))
  end

  it "fetches with credentials omit, cors mode, and a sane referrer policy" do
    expect(source).to include('credentials: "omit"')
    expect(source).to include('mode: "cors"')
    # Either "no-referrer" or "strict-origin-when-cross-origin" is acceptable —
    # both preserve the cross-origin privacy posture while supporting the
    # same-origin test setup.
    expect(source).to match(/referrerPolicy: "(no-referrer|strict-origin-when-cross-origin)"/)
  end

  it "caps payload at 256 KB (262144 bytes)" do
    expect(source).to include("262144")
  end

  it "rejects non-JSON content types" do
    expect(source).to include("application/json")
    expect(source).to match(/unexpected content-type/)
  end

  it "gates on the data-consent attribute" do
    expect(source).to match(/getAttribute\(["']data-consent["']\)/),
                       "widget must read the data-consent attribute"
    # The guard must short-circuit (return) when consent is present but not granted.
    expect(source).to match(/consent[\s\S]{0,80}!==\s*["']granted["'][\s\S]{0,80}return/),
                       "widget must no-op when data-consent is present and not 'granted'"
  end
end
