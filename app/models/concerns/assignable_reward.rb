# For anything that hands a Reward to a customer later (campaign, stamp card,
# badge…): refuse to attach a reward that cannot be handed out. Such a config
# looks fine in the merchant UI but pays out nothing — the customer fills the
# card, or scans the QR, and receives silence.
#
# Only checked when the reward is attached or swapped, so an existing row whose
# prize ran out afterwards stays editable (and keeps its reward).
module AssignableReward
  extend ActiveSupport::Concern

  included do
    validate :reward_must_be_assignable, if: -> { reward_id_changed? && reward.present? }
  end

  private

  def reward_must_be_assignable
    reason = reward.unassignable_reason
    return if reason.nil?
    # :base — the form prints full_messages, and an attribute prefix would read
    # as "Reward ..." in front of an already complete sentence.
    errors.add(:base, I18n.t("merchant.rewards.reward_unavailable",
                             title: reward.title, reason: reason))
  end
end
