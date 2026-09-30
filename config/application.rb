require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Loyalty
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Timezone
    config.time_zone = "Asia/Ho_Chi_Minh"

    # i18n — bilingual Vietnamese / English (VI default)
    config.i18n.default_locale = :vi
    config.i18n.available_locales = [ :vi, :en ]
    config.i18n.fallbacks = [ :en ]
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]

    # Generators — lean models, no extra cruft
    config.generators do |g|
      g.test_framework :test_unit, fixture: false
      g.helper false
      g.assets false
      g.factory_bot dir: "test/factories"
    end
  end
end
