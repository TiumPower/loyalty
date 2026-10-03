# A one-time login code. The identifier is whatever the customer typed — an
# email or a phone number — and `channel` records how we tried to reach them.
#
# Keeping ONE identifier column (rather than an email column and a phone column)
# is what lets a single delivery layer serve email, Zalo ZNS and SMS without the
# callers caring which one a given customer uses.
class OtpChallenge < ApplicationRecord
  acts_as_tenant(:workspace)

  TTL           = 10.minutes
  MAX_ATTEMPTS  = 5
  SCOPES        = %w[customer].freeze
  DEFAULT_SCOPE = "customer"
  CHANNELS      = %w[email sms zalo].freeze


  belongs_to :workspace

  validates :identifier, :code, presence: true
  validates :scope,   inclusion: { in: SCOPES }
  validates :channel, inclusion: { in: CHANNELS }

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  # Issue (or re-issue) a code. `channel` is normally chosen for us; pin it when
  # the point of the flow is to prove control of a specific address — see the
  # email-change flow in Customer::ProfileController.
  def self.issue!(identifier:, scope: DEFAULT_SCOPE, workspace: nil,
                  purpose: "login", channel: nil)
    ident = normalize(identifier)
    challenge = create!(
      identifier: ident, scope: scope, workspace: workspace, purpose: purpose,
      channel: channel || pick_channel(identifier: ident, workspace: workspace),
      code: format("%06d", SecureRandom.random_number(1_000_000)),
      expires_at: TTL.from_now
    )
    challenge.deliver!
    challenge
  end

  # `purpose` is part of the lookup, not a detail: without it an email-change
  # code would log you in, and a login code would confirm an address change.
  def self.latest_for(identifier:, scope: DEFAULT_SCOPE, workspace: nil, purpose: "login")
    where(identifier: normalize(identifier), scope: scope,
          workspace_id: workspace&.id, purpose: purpose)
      .order(created_at: :desc).first
  end

  # Canonicalised by SHAPE, not by scope: this app accepts an email and a phone
  # under the same scope, so the scope cannot tell us which one we were handed.
  def self.normalize(identifier)
    raw = identifier.to_s.strip
    return raw.downcase if raw.include?("@")
    Member.canonical_phone(raw).presence || raw.downcase
  end

  # An email address goes by email. A phone goes over Zalo — but only once a
  # live send has actually succeeded (AppSetting "zns_verified_at"). Until then
  # prefer a channel we know works, so configuring the ENV does not silently
  # take a working email channel away from customers who have one.
  def self.pick_channel(identifier:, workspace: nil)
    return "email" if identifier.to_s.include?("@")
    return "zalo"  if OtpSender.configured? && AppSetting.get("zns_verified_at").present?
    return "email" if EmailOtp.configured? && email_for_phone(identifier, workspace).present?
    "zalo"
  end

  def self.email_for_phone(phone, workspace)
    return nil if workspace.nil?
    Member.unscoped.where(workspace_id: workspace.id, phone: phone)
          .where.not(email: nil).pick(:email)
  end

  # Where an emailed code should go. For a phone identifier that is whatever
  # address the member happens to have on file, if any.
  def delivery_email
    return identifier if identifier.to_s.include?("@")
    return nil if workspace_id.blank?
    Member.unscoped.where(workspace_id: workspace_id, phone: identifier).pick(:email)
  end

  def deliver!
    if channel == "email"
      OtpMailer.login_code(self).deliver_later if deliverable?
    elsif OtpSender.configured?
      # The id, never the code: a code in the job payload would also live in
      # Redis, in Sidekiq's retry set and in any error report of a failed job.
      OtpDeliveryJob.perform_later(id)
    end
    Rails.logger.info(
      "[OTP] ws=#{workspace&.subdomain} scope=#{scope} channel=#{channel} " \
      "ident=#{log_identifier}#{" code=#{code}" if show_on_screen?}"
    )
  end

  # Whether any channel can actually reach this person right now.
  def deliverable?
    if channel == "email"
      EmailOtp.configured? && delivery_email.present?
    else
      OtpSender.configured?
    end
  end

  # A code may be printed on screen only when an operator explicitly asked for
  # it, or when there is genuinely no way to deliver it.
  #
  # Deliberately NOT a function of `delivery_error`: if a failed send revealed
  # the code, one vendor outage would become an auth bypass for every account
  # on the platform.
  def show_on_screen?
    return true unless Rails.env.production?
    return true if operator_override?
    !deliverable?
  end

  def verify(input)
    return :expired if expires_at < Time.current || consumed_at.present?
    increment!(:attempts)
    return :too_many if attempts > MAX_ATTEMPTS
    return :mismatch unless ActiveSupport::SecurityUtils.secure_compare(code, input.to_s)
    update!(consumed_at: Time.current)
    :ok
  end

  private

  def operator_override?
    AppSetting.show_otp? || ENV["SHOW_OTP"] == "true"
  end

  # Only ever log the code when we are already printing it on the customer's
  # screen; the log is retained across releases and the screen is not.
  def log_identifier
    identifier.to_s.include?("@") ? identifier : PhoneFormat.mask(identifier)
  end
end
