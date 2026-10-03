require "test_helper"

# Merging is destructive and irreversible, so the cases that matter are the ones
# where a naive `update_all(member_id:)` would raise or lose data: the six unique
# indexes that include member_id, and the associations declared
# `dependent: :destroy`.
class MemberMergeTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "mergetest")
    ActsAsTenant.current_tenant = @ws
    WorkspaceBootstrap.call(@ws) if defined?(WorkspaceBootstrap)
    @keeper = create(:member, workspace: @ws, email: "keep@example.com", name: "Chị Lan")
    @loser  = create(:member, workspace: @ws, email: nil, phone: "0901234567")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def merge! = MemberMerge.call(keeper: @keeper.reload, loser: @loser.reload)

  # ---- guards -------------------------------------------------------------

  test "a member cannot be merged into itself" do
    result = MemberMerge.call(keeper: @keeper, loser: @keeper)
    assert_not result.ok?
  end

  test "two shops' members cannot be merged" do
    other = create(:workspace, subdomain: "othershop")
    stranger = ActsAsTenant.with_tenant(other) { create(:member, workspace: other) }
    result = MemberMerge.call(keeper: @keeper, loser: stranger)
    assert_not result.ok?
    assert stranger.reload.persisted?
  end

  # ---- the ledger ---------------------------------------------------------

  test "the points ledger moves across and the balance is recomputed" do
    PointTransaction.create!(workspace: @ws, member: @keeper, amount: 100, kind: "earn")
    PointTransaction.create!(workspace: @ws, member: @loser,  amount: 250, kind: "earn")

    assert merge!.ok?
    assert_equal 350, @keeper.reload.points_balance
    assert_equal 2, PointTransaction.where(member_id: @keeper.id).count
    assert_not Member.exists?(@loser.id)
  end

  # A merge is bookkeeping. Telling the customer "Gold unlocked 🎉" because an
  # operator tidied up their duplicate profiles would be a lie.
  test "crossing a tier line during a merge does not notify the customer" do
    tier = @ws.tiers.where("threshold_points > 0").order(:threshold_points).last
    skip "no tiers seeded" if tier.nil?

    PointTransaction.create!(workspace: @ws, member: @loser, amount: tier.threshold_points + 10, kind: "earn")
    assert_no_difference -> { Notification.where(kind: "tier_up").count } do
      assert merge!.ok?
    end
    assert_equal tier.key, @keeper.reload.tier_key
  end

  # ---- unique indexes -----------------------------------------------------

  test "a badge both profiles hold is not duplicated" do
    badge = Badge.create!(workspace: @ws, key: "merge-test", name: "Khách quen")
    MemberBadge.create!(workspace: @ws, member: @keeper, badge: badge, earned_at: 2.days.ago)
    MemberBadge.create!(workspace: @ws, member: @loser,  badge: badge, earned_at: 1.day.ago)

    assert merge!.ok?
    assert_equal 1, MemberBadge.where(member_id: @keeper.id, badge_id: badge.id).count
  end

  test "stamps on two cards for the same shop add up onto one card" do
    card = StampCard.create!(workspace: @ws, title: "Thẻ cà phê", target_count: 10)
    StampCardMembership.create!(workspace: @ws, member: @keeper, stamp_card: card, count: 3)
    StampCardMembership.create!(workspace: @ws, member: @loser,  stamp_card: card, count: 4,
                                last_stamp_at: 1.hour.ago)

    assert merge!.ok?
    rows = StampCardMembership.where(member_id: @keeper.id, stamp_card_id: card.id)
    assert_equal 1, rows.count
    assert_equal 7, rows.first.count, "stamps the customer actually earned must not be thrown away"
  end

  test "the same device subscribed under both profiles keeps one subscription" do
    %w[keeper loser].each_with_index do |_, i|
      PushSubscription.create!(workspace: @ws, member: (i.zero? ? @keeper : @loser),
                               endpoint: "https://push.example/same", p256dh: "k", auth: "a")
    end
    assert merge!.ok?
    assert_equal 1, PushSubscription.where(member_id: @keeper.id).count
  end

  test "distinct devices are both kept" do
    PushSubscription.create!(workspace: @ws, member: @keeper, endpoint: "https://push.example/a",
                             p256dh: "k", auth: "a")
    PushSubscription.create!(workspace: @ws, member: @loser, endpoint: "https://push.example/b",
                             p256dh: "k", auth: "a")
    assert merge!.ok?
    assert_equal 2, PushSubscription.where(member_id: @keeper.id).count
  end

  # ---- identity -----------------------------------------------------------

  # The whole reason a duplicate exists: one profile has the email, the other the
  # phone. The survivor must end up able to log in either way.
  test "the survivor adopts the identifier it was missing" do
    assert merge!.ok?
    @keeper.reload
    assert_equal "keep@example.com", @keeper.email
    assert_equal "0901234567", @keeper.phone, "otherwise the customer can no longer log in by phone"
  end

  test "the keeper's own identifiers are never overwritten" do
    @keeper.update!(phone: "0907654321")
    assert merge!.ok?
    assert_equal "0907654321", @keeper.reload.phone
  end

  # Both identifiers are unique per workspace, so anything the survivor could
  # not adopt is destroyed with the row — it has to be written down somewhere.
  test "what the merged-away profile carried is recorded on the survivor" do
    loser_id = @loser.id
    assert merge!.ok?
    trace = @keeper.reload.settings["merged_from"]
    assert_equal 1, trace.size
    assert_equal loser_id, trace.first["id"]
    assert_equal "0901234567", trace.first["phone"]
    assert trace.first["at"].present?
  end

  test "a blank name on the survivor is filled from the other profile" do
    @keeper.update_columns(name: "")
    @loser.update!(name: "Chị Lan Nguyễn")
    assert merge!.ok?
    assert_equal "Chị Lan Nguyễn", @keeper.reload.name
  end

  # ---- referrals ----------------------------------------------------------

  test "people referred by the merged-away profile are repointed" do
    invited = create(:member, workspace: @ws, referred_by_id: @loser.id)
    assert merge!.ok?
    assert_equal @keeper.id, invited.reload.referred_by_id
  end

  test "the survivor never ends up referring itself" do
    @keeper.update_columns(referred_by_id: @loser.id)
    assert merge!.ok?
    assert_nil @keeper.reload.referred_by_id
  end

  test "only one referral-received record survives" do
    inviter = create(:member, workspace: @ws)
    Referral.create!(workspace: @ws, referrer: inviter, referred: @keeper)
    Referral.create!(workspace: @ws, referrer: inviter, referred: @loser)
    assert merge!.ok?
    assert_equal 1, Referral.where(referred_id: @keeper.id).count
  end

  # ---- history that `dependent: :destroy` would have eaten ---------------

  test "vouchers and history survive the merge rather than being destroyed with the row" do
    Notification.create!(workspace: @ws, member: @loser, kind: "generic", title: "Xin chào")
    assert merge!.ok?
    assert_equal 1, Notification.where(member_id: @keeper.id).count
  end
end
