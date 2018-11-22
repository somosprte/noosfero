require 'selenium-webdriver'

Capybara.default_driver = :selenium
Capybara.register_driver :selenium do |app|
  case ENV['SELENIUM_DRIVER']
  when 'chrome'
    options = Selenium::WebDriver::Chrome::Options.new
    driver = Selenium::WebDriver.for :chrome, options: options
  else
    profile = Selenium::WebDriver::Firefox::Profile.new
    profile.native_events = true
    profile["intl.accept_languages"] = "en"
    options = Selenium::WebDriver::Firefox::Options.new
    options.profile = profile
    driver = Selenium::WebDriver.for :firefox, options: options
  end
end

Before('@ignore-hidden-elements') do
  Capybara.ignore_hidden_elements = true
end

Capybara.default_max_wait_time = 60
Capybara.server_host = "localhost"

World(Capybara)
