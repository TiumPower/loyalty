require "test_helper"

# When a card is held, both sides must hear about it: the customer sees their
# stamps are safe, and the merchant — the only one who can fix it — gets an alert.
class StampHoldNoticeTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "holdnotice", status: "trial")
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws).update!(gamification_enabled: true)
      # Attach while it still has stock (the picker refuses a sold-out one),
      # then let it run out — which is how this happens in a real shop.
      @reward = Reward.create!(workspace: @ws, title: "Cà phê", kind: "gift", value_unit: "item",
                               active: true, stock: 1)
      @card = StampCard.create!(workspace: @ws, title: "Mua 2 tặng 1", target_count: 2,
                                reward: @reward, active: true)
      @reward.update_columns(redeemed_count: 1)
      @member = create(:member, workspace: @ws)
      @sm = @card.membership_for(@member)
    end
  end

  test "the customer is told once, and the merchant gets one actionable alert" do
    ActsAsTenant.with_tenant(@ws) do
      2.times { Gamification.advance_stamps(@member, @ws) }
      notices = Notification.where(member_id: @member.id).to_a
      assert_equal 1, notices.size
      assert_equal I18n.t("customer.stamps.held_notice_title"), notices.first.title

      alerts = MerchantAlert.where(kind: "reward_stock").to_a
      assert_equal 1, alerts.size
      assert_equal "danger", alerts.first.level
      assert_match @card.title, alerts.first.title

      # More stamps on a held card must not spam either inbox.
      Gamification.advance_stamps(@member, @ws)
      assert_equal 1, Notification.where(member_id: @member.id).count
      assert_equal 1, MerchantAlert.where(kind: "reward_stock").count
    end
  end

  test "the stamps page tells the customer their stamps are safe" do
    ActsAsTenant.with_tenant(@ws) { 2.times { Gamification.advance_stamps(@member, @ws) } }
    sign_in_member
    get "/w/#{@ws.slug}/stamps"
    assert_response :success
    assert_match I18n.t("customer.stamps.held_title"), response.body
    assert_match I18n.t("customer.stamps.held_body", reward: "Cà phê"), response.body
  end

  # Restocking from the merchant screen is the fix — it must pay out by itself.
  test "restocking the reward queues the settle job" do
    ActsAsTenant.with_tenant(@ws) { 2.times { Gamification.advance_stamps(@member, @ws) } }
    user = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: user, workspace: @ws, role: "owner") }
    sign_in user

    assert_enqueued_with(job: SettleHeldStampCardsJob, args: [@reward.id]) do
      patch "/merchant/rewards/#{@reward.id}", params: {
        reward: { title: "Cà phê", kind: "gift", value_unit: "item", value: 0, stock: 5, active: "1" }
      }
    end

    perform_enqueued_jobs
    sm = ActsAsTenant.with_tenant(@ws) { @card.membership_for(@member) }
    assert_equal 0, sm.count, "the held card was not paid out after restocking"
    assert_equal 1, sm.completed_count
    assert_equal 1, ActsAsTenant.with_tenant(@ws) { Voucher.where(member_id: @member.id).count }
  end

  private

  def sign_in_member
    post "/w/#{@ws.slug}/login", params: { email: @member.email }
    code = ActsAsTenant.with_tenant(@ws) { OtpChallenge.order(:created_at).last.code }
    post "/w/#{@ws.slug}/verify", params: { code: code }
  end
end
