require_relative 'boot'

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "sprockets/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Clientcomm
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.0
    config.active_record.belongs_to_required_by_default = false

    # validate Twilio POSTs
    # see https://www.twilio.com/blog/2014/09/securing-your-ruby-webhooks-with-rack-middleware.html
    # see https://github.com/twilio/twilio-ruby/blob/master/lib/rack/twilio_webhook_authentication.rb
    config.middleware.use Rack::TwilioWebhookAuthentication, ENV['TWILIO_AUTH_TOKEN'], '/incoming'

    # Use delayed job for the job queue
    config.active_job.queue_adapter = :delayed_job


    # Configure external DSN
    if ENV['SENTRY_ENDPOINT']
      Raven.configure do |config|
        config.dsn = ENV['SENTRY_ENDPOINT']
        config.tags = { instance_name: ENV['DEPLOYMENT'] }
      end
    end

    # Set the time zone from ENV, or default to UTC
    config.time_zone = ENV['TIME_ZONE'] || 'UTC'

    Dir.glob(Rails.root.join('app', 'assets', 'images', '**')).each do |path|
      config.assets.paths << path
    end


    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
