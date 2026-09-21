# Runs after a prize is restocked / re-enabled: hands the reward to every
# customer whose stamp card has been sitting full waiting for it. Off the
# request so a big shop's restock doesn't block the merchant's page.
class SettleHeldStampCardsJob < ApplicationJob
  queue_as :default

  def perform(reward_id)
    reward = ActsAsTenant.without_tenant { Reward.find_by(id: reward_id) } or return
    n = Gamification.settle_held_cards(reward)
    Rails.logger.info("[SettleHeldStampCards] reward=#{reward_id} settled=#{n}") if n.positive?
  end
end
