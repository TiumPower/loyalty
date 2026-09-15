source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.2.3", ">= 7.2.3.2"
# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Redis — cache, sessions, ActionCable, Sidekiq
gem "redis", ">= 4.0.1"
gem "rack-attack"
gem "connection_pool", "~> 2.4"

# --- Dynamic Loyalty stack (mirrors Orbit CRM / VOX) ---
# Authentication & Authorization
gem "devise"
gem "devise-i18n"
gem "pundit"

# Multi-tenancy (row-level, workspace_id)
gem "acts_as_tenant"

# Slugs
gem "friendly_id", "~> 5.5"

# Background jobs
gem "sidekiq"
gem "sidekiq-cron"

# AI — Anthropic Claude API (used in later phases)
gem "faraday"
gem "faraday-retry"

# Charts
gem "web-push"
gem "chartkick"
gem "groupdate"

# QR code generation (member/promo/voucher codes)
gem "rqrcode"

# File uploads / image variants
gem "image_processing", "~> 2.1"
# S3 client — dùng cho DigitalOcean Spaces (xem config/storage.yml)
gem "aws-sdk-s3", require: false

# Env management
gem "dotenv-rails"

# Demo/seed data (used by db/seeds.rb in all environments)
gem "faker"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Error monitoring. Inert until SENTRY_DSN is set, so development and any
# deploy without a DSN behave exactly as before.
gem "sentry-ruby"
gem "sentry-rails"
gem "sentry-sidekiq"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Test data
  gem "factory_bot_rails"

  # Deployment (Capistrano, mirrors VOX)
  gem "capistrano",         "~> 3.18", require: false
  gem "capistrano-rails",   "~> 1.6",  require: false
  gem "capistrano-rbenv",   "~> 2.2",  require: false
  gem "capistrano3-puma",   "~> 6.0",  require: false
  gem "capistrano-sidekiq", "~> 2.3",  require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
