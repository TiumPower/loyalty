require "test_helper"

# The reward catalogue: what a shop gives away for points.
class RewardCatalogueTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "rewards")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @reward = Reward.create!(workspace: @ws, title: "Cà phê", kind: "voucher",
                               cost_points: 100, value_unit: "item", active: true)
      @member = create(:member, workspace: @ws)
    end
    sign_in @user
  end

  test "a reward nobody has claimed can be deleted outright" do
    assert_difference -> { Reward.unscoped.where(workspace_id: @ws.id).count }, -1 do
      delete "/merchant/rewards/#{@reward.id}"
    end
  end

  # Hard-deleting would take the customer's voucher and its history with it.
  test "a reward with issued vouchers is archived, not destroyed" do
    ActsAsTenant.with_tenant(@ws) do
      Voucher.create!(workspace: @ws, member: @member, reward: @reward, state: "active")
    end

    assert_no_difference -> { Reward.unscoped.where(workspace_id: @ws.id).count } do
      delete "/merchant/rewards/#{@reward.id}"
    end
    @reward.reload
    assert_not @reward.active?
    assert @reward.archived_at.present?
    assert_equal 1, ActsAsTenant.with_tenant(@ws) { Voucher.where(reward_id: @reward.id).count }
  end

  test "a reward attached to a campaign is refused, not silently detached" do
    ActsAsTenant.with_tenant(@ws) do
      Campaign.create!(workspace: @ws, name: "Tết", reward: @reward, campaign_type: "promo_voucher")
    end

    assert_no_difference -> { Reward.unscoped.where(workspace_id: @ws.id).count } do
      delete "/merchant/rewards/#{@reward.id}"
    end
    assert @reward.reload.active?, "the reward was switched off despite the campaign still using it"
  end

  # Two customers hitting the last unit at once must not both get it.
  test "limited stock cannot be over-claimed" do
    ActsAsTenant.with_tenant(@ws) do
      @reward.update!(stock: 1)
      2.times do |i|
        m = create(:member, workspace: @ws)
        m.point_transactions.create!(workspace: @ws, kind: "earn", amount: 500)
        m.recompute_points!
        RedeemReward.new(member: m, reward: @reward).call
      end
      assert_equal 1, @reward.reload.redeemed_count, "stock was claimed twice"
      assert_equal 1, Voucher.where(reward_id: @reward.id).count
    end
  end

  test "remaining stock never reads as a negative number" do
    ActsAsTenant.with_tenant(@ws) do
      @reward.update!(stock: 2, redeemed_count: 5) # merchant lowered stock after the fact
      assert_equal 0, @reward.remaining
      assert_not @reward.in_stock?
    end
  end
end

# Campaigns push notifications to every customer in a segment.
class CampaignBroadcastTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "campaigns")
    ActsAsTenant.current_tenant = @ws
    reward = Reward.create!(workspace: @ws, title: "Quà", kind: "gift", cost_points: 0, value_unit: "item")
    @campaign = Campaign.create!(workspace: @ws, name: "Khai trương", campaign_type: "promo_voucher",
                                 status: "running", audience: "all", reward: reward)
    @members = 3.times.map { create(:member, workspace: @ws) }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  # broadcasts.campaign_id exists with an index and Campaign declares
  # has_many :broadcasts, but Broadcast never declared its side — so
  # CampaignsController#push raised UnknownAttributeError on every send.
  test "a broadcast can be attached to the campaign that sent it" do
    assert Broadcast.reflect_on_association(:campaign), "Broadcast has no campaign association"

    broadcast = @ws.broadcasts.create!(campaign: @campaign, segment_key: "all",
                                       audience_label: "Tất cả", title: "T", body: "B")
    assert_equal @campaign.id, broadcast.campaign_id
    assert_equal [broadcast], @campaign.reload.broadcasts.to_a
  end

  test "delivering writes one notification per customer and records the count" do
    broadcast = @ws.broadcasts.create!(campaign: @campaign, segment_key: "all",
                                       audience_label: "Tất cả", title: "T", body: "B")
    assert_difference -> { Notification.count }, 3 do
      broadcast.deliver!(@members)
    end
    assert_equal 3, broadcast.reload.sent_count
    assert broadcast.sent_at.present?
  end

  test "a campaign knows it has already been sent" do
    assert_empty @campaign.broadcasts.where.not(sent_at: nil)

    b = @ws.broadcasts.create!(campaign: @campaign, segment_key: "all",
                               audience_label: "Tất cả", title: "T", body: "B")
    b.deliver!(@members)

    sent = @campaign.reload.broadcasts.where.not(sent_at: nil)
    assert_equal 1, sent.count
    assert_equal 3, sent.first.sent_count
  end

  test "pausing a campaign switches its promo QR off" do
    reward = Reward.create!(workspace: @ws, title: "R", kind: "gift", cost_points: 0, value_unit: "item")
    promo = PromoCode.create!(workspace: @ws, campaign: @campaign, reward: reward, token: "tok123", active: true)

    @campaign.update!(status: "paused")
    @campaign.promo_codes.update_all(active: false)
    assert_not promo.reload.active?
  end
end
