require "rails_helper"

RSpec.describe "Host configuration" do
  describe "default_url_options" do
    it "uses CHIBICHANGE_HOST when set" do
      with_env("CHIBICHANGE_HOST" => "test.example.com") do
        config = HostConfig.compute
        expect(config[:default_url_options]).to include(host: "test.example.com")
      end
    end

    it "uses https protocol when force_ssl is enabled" do
      with_env("CHIBICHANGE_HOST" => "test.example.com", "CHIBICHANGE_FORCE_SSL" => "true") do
        config = HostConfig.compute
        expect(config[:default_url_options]).to include(protocol: "https")
      end
    end

    it "uses http protocol when force_ssl is disabled" do
      with_env("CHIBICHANGE_HOST" => "test.example.com", "CHIBICHANGE_FORCE_SSL" => "false") do
        config = HostConfig.compute
        expect(config[:default_url_options]).to include(protocol: "http")
      end
    end
  end

  describe "widget_host" do
    it "defaults to https://CHIBICHANGE_HOST when CHIBICHANGE_WIDGET_HOST is unset" do
      with_env("CHIBICHANGE_HOST" => "app.example.com", "CHIBICHANGE_WIDGET_HOST" => nil) do
        expect(HostConfig.compute[:widget_host]).to eq "https://app.example.com"
      end
    end

    it "uses CHIBICHANGE_WIDGET_HOST verbatim when set" do
      with_env("CHIBICHANGE_HOST" => "app.example.com",
               "CHIBICHANGE_WIDGET_HOST" => "https://cdn.example.com") do
        expect(HostConfig.compute[:widget_host]).to eq "https://cdn.example.com"
      end
    end
  end

  describe "force_ssl?" do
    it "is true by default" do
      with_env("CHIBICHANGE_FORCE_SSL" => nil) do
        expect(HostConfig.force_ssl?).to be true
      end
    end

    it "is false when explicitly disabled" do
      with_env("CHIBICHANGE_FORCE_SSL" => "false") do
        expect(HostConfig.force_ssl?).to be false
      end
    end

    it "is true for any truthy string" do
      with_env("CHIBICHANGE_FORCE_SSL" => "true") do
        expect(HostConfig.force_ssl?).to be true
      end
    end
  end

  describe "validate_production!" do
    it "raises if CHIBICHANGE_HOST is missing in production" do
      with_env("CHIBICHANGE_HOST" => nil) do
        expect { HostConfig.validate_production! }.to raise_error(/CHIBICHANGE_HOST/)
      end
    end

    it "raises if RAILS_MASTER_KEY is missing in production" do
      with_env("CHIBICHANGE_HOST" => "x.example.com", "RAILS_MASTER_KEY" => nil) do
        expect { HostConfig.validate_production! }.to raise_error(/RAILS_MASTER_KEY/)
      end
    end

    it "passes when all required vars are present" do
      with_env(
        "CHIBICHANGE_HOST" => "x.example.com",
        "RAILS_MASTER_KEY" => "abcdef1234567890",
        "DATABASE_URL"     => "postgres://localhost/chibichange"
      ) do
        expect { HostConfig.validate_production! }.not_to raise_error
      end
    end
  end

  def with_env(overrides)
    originals = {}
    overrides.each do |k, v|
      originals[k] = ENV[k]
      ENV[k] = v
    end
    yield
  ensure
    originals.each { |k, v| ENV[k] = v }
  end
end
