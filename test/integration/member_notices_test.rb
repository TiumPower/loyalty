require "test_helper"

# Two moments the design puts in the customer's inbox — "Gold tier unlocked 🎉"
# and "Friend joined!" — that the app used to pass over in silence: the tier
# column changed, both sides of a referral were paid, and nobody was told.
class MemberNoticesTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "notices")
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, referral_enabled: true, referral_points: 200,
                               earn_points: 1, earn_per_amount: 10_000)
      @bronze = @ws.tiers.find_by(key: "bronze") ||
                @ws.tiers.create!(key: "bronze", name: "Đồng", threshold_points: 0, position: 0)
      @silver = @ws.tiers.find_by(key: "silver") ||
                @ws.tiers.create!(key: "silver", name: "Bạc", threshold_points: 500, position: 1)
      @member = create(:member, workspace: @ws)
    end
  end

  def credit(member, amount, kind: "earn")
    ActsAsTenant.with_tenant(@ws) do
      PointTransaction.create!(workspace: @ws, member: member, kind: kind, amount: amount)
      member.recompute_points!
    end
  end

  test "climbing a rung reaches the customer's inbox, named and linked" do
    ActsAsTenant.with_tenant(@ws) do
      credit(@member, @silver.threshold_points + 10)

      note = @member.notifications.order(:id).last
      assert note, "reaching a new tier should produce a notification"
      assert_match @silver.name, note.title
      assert_equal "/tier", note.deep_link
      assert_equal "silver", @member.reload.tier_key
    end
  end

  test "it is a promotion that is announced, not any change of rung" do
    ActsAsTenant.with_tenant(@ws) do
      credit(@member, @silver.threshold_points + 10)
      @member.notifications.delete_all

      # A voided bill drags the balance back under the threshold. Losing a rung
      # is not something to congratulate anyone for.
      credit(@member, -(@silver.threshold_points + 10), kind: "void")
      assert_equal "bronze", @member.reload.tier_key
      assert_empty @member.notifications.reload
    end
  end

  test "a recompute that changes nothing says nothing" do
    ActsAsTenant.with_tenant(@ws) do
      credit(@member, @silver.threshold_points + 10)
      @member.notifications.delete_all
      3.times { @member.recompute_points! }
      assert_empty @member.notifications.reload, "only the moment of promotion is news"
    end
  end

  test "a completed referral tells both sides, in their own language" do
    ActsAsTenant.with_tenant(@ws) do
      friend = create(:member, workspace: @ws, name: "Linh", locale: "en")
      Referrals.attach(referred: friend, referrer_code: @member.referral_code)

      outlet = @ws.outlets.first || Outlet.create!(workspace: @ws, name: "CN1", active: true)
      Purchase.create!(workspace: @ws, member: friend, outlet: outlet, amount: 100_000,
                       points_earned: 10)
      Referrals.on_purchase(friend)

      referrer_note = @member.notifications.order(:id).last
      assert referrer_note, "the person who invited should hear that it worked"
      assert_match "Linh", referrer_note.body
      assert_match "200", referrer_note.body

      # The invitee started with points they never earned; the inbox is the only
      # place that explains where they came from — and it speaks their language.
      friend_note = friend.notifications.order(:id).last
      assert friend_note, "the invitee should be told why they have points"
      assert_equal I18n.t("customer.notices.referral_welcome.title", locale: :en), friend_note.title
    end
  end
end
