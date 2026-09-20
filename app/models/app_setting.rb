# Platform-level key/value store (not tenant-scoped). Used for rotating Zalo ZNS
# OA tokens, and for platform switches the super admin flips at runtime (see
# `flag?`) — anything that must change without a deploy or an .env edit.
class AppSetting < ApplicationRecord
  def self.get(key) = find_by(key: key.to_s)&.value

  def self.set(key, value)
    rec = find_or_initialize_by(key: key.to_s)
    rec.update!(value: value.to_s)
    value
  end

  # --- Boolean switches ----------------------------------------------------
  # A flag is only "on" when it was explicitly turned on; a missing row is off.
  def self.flag?(key)
    get(key) == "true"
  rescue ActiveRecord::StatementInvalid
    # The table may not exist yet during an early boot / first migration.
    false
  end

  def self.set_flag(key, on)
    set(key, ActiveModel::Type::Boolean.new.cast(on) ? "true" : "false")
  end

  # Show the OTP code straight on the screen instead of only emailing it.
  # Meant for testing and demos — with it on, anyone who knows a member's email
  # can sign in as them, so the admin screen warns while it is enabled.
  SHOW_OTP_KEY = "show_otp".freeze

  def self.show_otp? = flag?(SHOW_OTP_KEY)
end
