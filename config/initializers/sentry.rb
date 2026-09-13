# Error monitoring.
#
# Entirely inert unless SENTRY_DSN is set, so development and any deploy
# without a DSN behave exactly as before — nothing is sent anywhere.
return if ENV["SENTRY_DSN"].blank?

Sentry.init do |config|
  config.dsn         = ENV["SENTRY_DSN"]
  config.environment = Rails.env
  # Capistrano writes REVISION into the release root, so errors are attributed
  # to the exact deploy that introduced them.
  rev = Rails.root.join("REVISION")
  config.release = ENV["CURRENT_REVISION"].presence || (rev.exist? ? rev.read.strip : nil)

  # Shops' customer lists (names, phones, birthdays) run through this app.
  # Never ship request bodies, cookies or IPs to a third party; the workspace
  # and user tags below are enough to find who hit a bug.
  config.send_default_pii = false
  config.max_request_body_size = :never
  config.send_client_reports = false

  filter = ActiveSupport::ParameterFilter.new(
    Rails.application.config.filter_parameters +
    %i[phone email otp code token birthday name]
  )
  config.before_send = lambda do |event, _hint|
    event.request&.data = filter.filter(event.request.data) if event.request&.data.is_a?(Hash)
    event
  end

  # Expected outcomes, not defects — they would bury the real errors.
  config.excluded_exceptions += %w[
    ActiveRecord::RecordNotFound
    ActionController::RoutingError
    ActionController::UnknownFormat
    ActionController::BadRequest
    ActsAsTenant::Errors::NoTenantSet
  ]

  config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_RATE", 0).to_f
end
