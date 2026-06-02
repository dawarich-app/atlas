require "capybara/rails"
require "capybara/rspec"
require "selenium/webdriver"

Capybara.default_driver = :rack_test

Capybara.register_driver :chibichange_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--window-size=1280,800")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.javascript_driver = :chibichange_chrome_headless
Capybara.server = :puma, { Silent: true }
