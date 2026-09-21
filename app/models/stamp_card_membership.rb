class StampCardMembership < ApplicationRecord
  acts_as_tenant(:workspace)

  belongs_to :workspace
  belongs_to :member
  belongs_to :stamp_card

  validates :member_id, uniqueness: { scope: :stamp_card_id }

  # Add one stamp; on reaching the target, issue the reward voucher and start a
  # fresh card. Returns { completed:, voucher:, held:, newly_held: }.
  #
  # `held` means the card is full but the prize could not be handed out (it ran
  # out). The card is then NOT spent: the stamps stay on it and it pays out as
  # soon as the merchant restocks. It used to reset and count the completion
  # regardless, so a customer who bought the last cup got nothing and lost the
  # whole card with it — silently.
  def add_stamp!
    result = { completed: false, voucher: nil, held: false, newly_held: false }
    with_lock do
      was_full = count >= stamp_card.target_count
      self.count += 1
      self.last_stamp_at = Time.current
      if count >= stamp_card.target_count
        voucher = stamp_card.reward ? issue_reward! : nil
        if stamp_card.reward && voucher.nil?
          self.count = stamp_card.target_count # hold it full, don't run past the goal
          result[:held] = true
          result[:newly_held] = !was_full # only worth telling anyone about once
        else
          self.count = 0
          self.completed_count += 1
          result[:completed] = true
          result[:voucher] = voucher
        end
      end
      save!
    end
    result
  end

  # True when the card is sitting full, waiting for the prize to come back.
  def held_for_stock? = stamp_card.reward.present? && count >= stamp_card.target_count

  # Pay out a held card now that the prize is back in stock. Returns the voucher,
  # or nil when there was nothing to settle (or stock ran out again in between).
  # Without this the customer would have to buy one MORE item to trigger the
  # payout their full card already earned.
  def settle_held!
    voucher = nil
    with_lock do
      break unless held_for_stock?
      voucher = issue_reward!
      break if voucher.nil?
      self.count = 0
      self.completed_count += 1
      save!
    end
    voucher
  end

  # A completed card only pays out while the reward still has stock — this used
  # to write the Voucher straight out, so a prize limited to N suất was issued
  # indefinitely and redeemed_count never moved. Returning nil now HOLDS the
  # card (see #add_stamp!) instead of spending it.
  def issue_reward!
    reward = stamp_card.reward
    return nil unless reward.claim_stock!
    Voucher.create!(
      workspace: workspace, member: member, reward: reward,
      source: "campaign", state: "active", points_spent: 0,
      expires_at: reward.valid_days.days.from_now
    )
  end
end
