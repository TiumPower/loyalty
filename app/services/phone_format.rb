# Vietnamese phone numbers, in the two forms we need.
#
# The STORAGE form is the local one (0xxxxxxxxx) produced by
# Member.canonical_phone, and it is load-bearing in three places that must not
# change: the [workspace_id, phone] unique index, the login lookup, and the
# merchant UI. Both Zalo APIs want 84xxxxxxxxx instead, so that conversion is a
# vendor concern and lives here — one place, shared by every adapter.
module PhoneFormat
  module_function

  # 0901234567 -> 84901234567. Returns nil for anything that is not a plausible
  # Vietnamese mobile number, so an adapter can bail out BEFORE spending money
  # on a request that was never going to be delivered.
  def vn84(raw)
    local = Member.canonical_phone(raw).to_s
    return nil unless local.match?(/\A0\d{8,10}\z/)
    "84#{local[1..]}"
  end

  # For logs and error reports. A full phone number in a log file is the one
  # piece of an OTP flow we can avoid retaining.
  def mask(raw)
    digits = raw.to_s
    return "***" if digits.length < 7
    "#{digits[0, 4]}***#{digits[-3, 3]}"
  end
end
