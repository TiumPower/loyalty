# Sends a Zalo OTP out of band. Delivery leaves the request cycle because a
# vendor API call is a network round trip we must not make a customer (or a
# puma worker) wait on.
#
# Takes the challenge id, NOT the code: a code in the job arguments would also
# sit in Redis, in Sidekiq's retry/dead sets and in any error report for a
# failed job. The code stays in Postgres.
class OtpDeliveryJob < ApplicationJob
  queue_as :default

  # No retries. A code that arrives on the third attempt is worse than no code
  # at all — by then the customer has asked for a new one, and this one is
  # either expired or about to overwrite the one they are typing.
  discard_on StandardError

  def perform(challenge_id)
    # unscoped: a worker has no current tenant, and the row is addressed by id.
    challenge = OtpChallenge.unscoped.find_by(id: challenge_id)
    return if challenge.nil?
    return if challenge.consumed_at.present? || challenge.expires_at < Time.current

    result = OtpSender.deliver(phone: challenge.identifier, code: challenge.code)

    challenge.update_columns(
      delivery_provider: result.provider,
      delivery_error:    (result.ok? ? nil : result.error.to_s.presence),
      delivered_at:      (result.ok? ? Time.current : nil)
    )

    # The first send that actually works is what lets OtpChallenge.pick_channel
    # start routing phone logins to Zalo. Until then we keep whatever channel
    # we already know reaches people.
    AppSetting.set("zns_verified_at", Time.current.to_i.to_s) if result.ok?
  end
end
