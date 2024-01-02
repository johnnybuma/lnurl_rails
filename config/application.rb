require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module LnUrlRails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    #

    config.active_record.cache_versioning = false
    config.cache_store = :redis_store, "redis://localhost:6379/0/cache", { expires_in: 90.minutes }
    config.active_job.queue_adapter = :sidekiq


    config.after_initialize do
      #Uncomment before sending to Heroku!!!
      if Rails.env.production?
        system ("RAILS_ENV=production ruby daemon_start.rb start")
        sleep 5
        puts "Bitcoin Live Data Refresh Should be Working"
      else
        puts "The Environment loaded is in Development..."

      end





    end

  end
end
