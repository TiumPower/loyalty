require "test_helper"

# Three different mechanics hand out reward vouchers: the catalogue, the spin
# wheel and stamp cards. All three must respect the reward's stock.
class GamificationPayoutTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "payout")
    ActsAsTenant.current_tenant = @ws
    @ws.program.update!(gamification_enabled: true)
    @member = create(:member, workspace: @ws)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def limited_reward(stock: 1)
    Reward.create!(workspace: @ws, title: "Cà phê", kind: "gift", cost_points: 0,
                   value_unit: "item", stock: stock, valid_days: 30)
  end

  def fund(member, points)
    member.point_transactions.create!(workspace: @ws, kind: "earn", amount: points)
    member.recompute_points!
  end

  # --- the shared claim ---------------------------------------------------

  test "a unit can only be claimed while stock remains" do
    reward = limited_reward(stock: 2)
    assert reward.claim_stock!
    assert reward.claim_stock!
    assert_not reward.reload.claim_stock!, "claimed past the stock limit"
    assert_equal 2, reward.reload.redeemed_count
  end

  test "an unlimited reward always claims" do
    reward = Reward.create!(workspace: @ws, title: "Free", kind: "gift", cost_points: 0,
                            value_unit: "item", stock: nil)
    5.times { assert reward.claim_stock! }
  end

  # --- spin wheel ---------------------------------------------------------

  test "the wheel cannot give away more of a prize than there is stock" do
    reward = limited_reward(stock: 1)
    wheel = SpinWheel.create!(workspace: @ws, cost_points: 0, daily_free: true,
      segments: [{ "label" => "Cà phê", "weight" => 1, "kind" => "reward", "reward_id" => reward.id }])

    3.times { wheel.spin!(create(:member, workspace: @ws)) }

    assert_equal 1, Voucher.where(reward_id: reward.id).count, "the wheel over-issued the prize"
    assert_equal 1, reward.reload.redeemed_count
  end

  test "losing the stock race costs the customer nothing" do
    reward = limited_reward(stock: 0)
    wheel = SpinWheel.create!(workspace: @ws, cost_points: 0, daily_free: true,
      segments: [{ "label" => "Cà phê", "weight" => 1, "kind" => "reward", "reward_id" => reward.id }])

    result = wheel.spin!(@member)
    assert_nil result[:voucher]
    assert_nil result[:error], "the spin itself should still succeed"
  end

  # The cost used to be checked against the cached points_balance column.
  test "a paid spin cannot go through on a stale balance" do
    wheel = SpinWheel.create!(workspace: @ws, cost_points: 100, daily_free: false,
      segments: [{ "label" => "10", "weight" => 1, "kind" => "points", "value" => 10 }])
    @member.update_columns(points_balance: 500) # cached says 500, the ledger says 0

    result = wheel.spin!(@member)
    assert_equal :not_enough, result[:error]
    assert_equal 0, @member.point_transactions.sum(:amount), "points were moved on a stale balance"
  end

  test "a paid spin a customer can afford is charged once" do
    fund(@member, 300)
    wheel = SpinWheel.create!(workspace: @ws, cost_points: 100, daily_free: false,
      segments: [{ "label" => "none", "weight" => 1, "kind" => "none", "value" => 0 }])

    wheel.spin!(@member)
    assert_equal 200, @member.reload.points_balance
  end

  test "the daily free spin is free, the next one is not" do
    fund(@member, 300)
    wheel = SpinWheel.create!(workspace: @ws, cost_points: 100, daily_free: true,
      segments: [{ "label" => "none", "weight" => 1, "kind" => "none", "value" => 0 }])

    assert_equal 0, wheel.spin!(@member)[:cost]
    assert_equal 100, wheel.spin!(@member)[:cost]
    assert_equal 200, @member.reload.points_balance
  end

  # --- stamp cards --------------------------------------------------------

  test "a completed stamp card only pays out while stock remains" do
    reward = limited_reward(stock: 1)
    card = StampCard.create!(workspace: @ws, title: "Mua 2 tặng 1", target_count: 2,
                             reward: reward, active: true)

    2.times.map { create(:member, workspace: @ws) }.each do |m|
      sm = card.membership_for(m)
      2.times { sm.add_stamp! }
    end

    assert_equal 1, Voucher.where(reward_id: reward.id).count, "stamp cards over-issued the prize"
    assert_equal 1, reward.reload.redeemed_count
  end

  test "a card still completes and resets even when the prize ran out" do
    # Attaching a sold-out reward is refused now, so set the card up while the
    # prize is still available and let it run out afterwards — which is how this
    # happens in real life anyway.
    reward = limited_reward(stock: 1)
    card = StampCard.create!(workspace: @ws, title: "Mua 2 tặng 1", target_count: 2,
                             reward: reward, active: true)
    reward.update_columns(stock: 0)
    sm = card.membership_for(@member)

    sm.add_stamp!
    result = sm.add_stamp!

    assert result[:completed]
    assert_nil result[:voucher]
    assert_equal 0, sm.reload.count, "the card did not reset"
    assert_equal 1, sm.completed_count
  end

  # --- automations (welcome / birthday / win-back) -------------------------

  test "a birthday gift stops when the prize runs out" do
    reward = limited_reward(stock: 1)
    @ws.update!(settings: @ws.settings.merge("automations" => {
      "birthday" => { "enabled" => true, "reward_id" => reward.id.to_s }
    }))
    today = Date.current
    3.times { create(:member, workspace: @ws, birthday: Date.new(1990, today.month, today.day)) }

    Automations.run_birthday(today: today)

    assert_equal 1, Voucher.where(reward_id: reward.id).count, "the automation over-issued the gift"
    assert_equal 1, reward.reload.redeemed_count
  end

  test "a customer who could not be given the birthday gift is not told they were" do
    reward = limited_reward(stock: 0)
    @ws.update!(settings: @ws.settings.merge("automations" => {
      "birthday" => { "enabled" => true, "reward_id" => reward.id.to_s }
    }))
    today = Date.current
    m = create(:member, workspace: @ws, birthday: Date.new(1990, today.month, today.day))

    assert_no_difference -> { Notification.where(member_id: m.id).count } do
      Automations.run_birthday(today: today)
    end
  end

  test "a welcome gift respects the stock too" do
    reward = limited_reward(stock: 1)
    @ws.update!(settings: @ws.settings.merge("automations" => {
      "welcome" => { "enabled" => true, "reward_id" => reward.id.to_s }
    }))

    3.times { Automations.on_signup(create(:member, workspace: @ws)) }
    assert_equal 1, Voucher.where(reward_id: reward.id).count
  end

  # --- campaign QR claims --------------------------------------------------

  test "a promo QR cannot hand out more than the reward's stock" do
    reward = limited_reward(stock: 1)
    campaign = Campaign.create!(workspace: @ws, name: "C", campaign_type: "promo_voucher", reward: reward)
    promo = PromoCode.create!(workspace: @ws, campaign: campaign, reward: reward,
                              token: "tok1", active: true, max_claims: 100)

    results = 3.times.map { promo.claim!(create(:member, workspace: @ws)) }

    assert_equal 1, Voucher.where(reward_id: reward.id).count, "the QR over-issued the prize"
    assert_equal 2, results.count { |(_, err)| err == :unavailable }
  end

  test "stamps accumulate towards the target" do
    card = StampCard.create!(workspace: @ws, title: "Mua 3 tặng 1", target_count: 3, active: true)
    sm = card.membership_for(@member)

    2.times { sm.add_stamp! }
    assert_equal 2, sm.reload.count
    assert_equal 0, sm.completed_count
  end
end
