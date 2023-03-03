# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../config/environment', __dir__)
# Prevent database truncation if the environment is production
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'webmock/rspec'
require 'capybara/rails'
require 'capybara/rspec'
require 'rspec/rails/shared_contexts/action_cable'

RSpec::Rails::FeatureCheck.module_eval do
  module_function

  def has_action_cable_testing?
    true
  end
end


Dir[Rails.root.join('spec', 'support', '**', '*.rb')].each { |f| require f }

ActiveRecord::Migration.maintain_test_schema!

# For ApplicationJob testing
ActiveJob::Base.queue_adapter = :test

# Capybara settings
Capybara.server = :puma
Capybara.default_max_wait_time = 5


def headless_options
  browser_options = ::Selenium::WebDriver::Chrome::Options.new
  browser_options.args << '--headless' unless ENV['RSPEC_HEADED']
  browser_options.args << '--disable-gpu' if Gem.win_platform?
  browser_options
end

driver = ENV['RSPEC_HEADED'] ? :chorme : :headless_chrome

 Capybara.register_driver driver do |app|
  browser_options = headless_options
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: browser_options)
end
Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new(app, browser: :chrome)
end

Capybara.javascript_driver = driver

# change to ':accessible_poltergeist' for accessibility warnings
# NOTE: you'll need to include the capybara-accessible gem
# Capybara.javascript_driver = :poltergeist

WebMock.disable_net_connect!(allow_localhost: true)

RSpec::Matchers.define :have_ignoring_newlines do |string|
  match do |page|
    case string
    when String
      return page.text.tr("\n"," ").include? string
    when Regexp
      return string.match page.text.tr("\n"," ")
    end
  end

  failure_message do |actual|
    "expected to find #{string.inspect} in:\n#{actual.text}"
  end

  failure_message_when_negated do |actual|
    "expected not to find #{string.inspect} in:\n#{actual.text}"
  end
end


RSpec.configure do |config|
  config.fixture_path = ::Rails.root.join('spec', 'fixtures')
  config.infer_spec_type_from_file_location!
  config.include ActiveSupport::Testing::TimeHelpers
  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # custom helpers, including steps
  config.include AnalyticsHelper
  config.include ResponsiveHelper
  config.include TwilioHelper
  config.include FeatureHelper, type: :feature
  config.include RequestHelper, type: :request
  # FactoryBot methods
  config.include FactoryBot::Syntax::Methods
  # Devise setup
  config.include Warden::Test::Helpers
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::ControllerHelpers, type: :view
  config.include Devise::Test::ControllerHelpers, type: :helper
  # So we can use dom_id
  config.include ActionView::RecordIdentifier
  config.include Rails.application.routes.url_helpers

  config.around :each, type: :feature do |example|
    ActionMailer::Base.deliveries.clear
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
    example.run
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = false
  end

  config.after :each, type: :feature, js: true do
    wait_for_ajax
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
