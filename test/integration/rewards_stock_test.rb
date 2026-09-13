require "test_helper"

# The rewards screen writes the rules the redemption paths spend points against,
# so anything it accepts becomes a promise to a customer.
class RewardsStockTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace)
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @owner = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000)
      @ws.memberships.create!(user: @owner, role: "owner")
      @member = create(:member, workspace: @ws)
      @member.point_transactions.create!(workspace: @ws, kind: "earn", amount: 1_000)
      @member.recompute_points!
    end
    sign_in @owner
  end

  def build_reward(attrs = {})
    ActsAsTenant.with_tenant(@ws) do
      @ws.rewards.new({ title: "Cà phê miễn phí", kind: "voucher", value_unit: "vnd",
                        value: 0, cost_points: 100, active: true, valid_days: 30 }.merge(attrs))
    end
  end

  # cost_points had no validation, so a negative one passed straight into
  # RedeemReward: the balance check trivially succeeded and the debit became a
  # credit. Redeeming printed points for the customer.
  test "a negative point cost is refused" do
    r = build_reward(cost_points: -500)
    refute r.valid?
    assert_includes r.errors.attribute_names, :cost_points

    ActsAsTenant.with_tenant(@ws) do
      ok = build_reward(cost_points: 100)
      ok.save!
      before = @member.reload.points_balance
      RedeemReward.new(member: @member.reload, reward: ok).call
      assert_equal before - 100, @member.reload.points_balance, "redeeming spends points"
    end
  end

  # An F&B happy hour that runs past midnight is ordinary. (22..2) is an empty
  # Ruby range, so the window was shut at every hour of the day — including 22h
  # and 23h — while the form cheerfully summarised it as "22h–02h".
  test "a window that runs past midnight is open on both sides of midnight" do
    r = build_reward(schedule: { "windows" => [{ "days" => [], "from_hour" => 22, "to_hour" => 2 }] })
    ActsAsTenant.with_tenant(@ws) do
      { 22 => true, 23 => true, 0 => true, 1 => true, 2 => true,
        3 => false, 12 => false, 21 => false }.each do |hour, expected|
        at = Time.zone.now.change(hour: hour)
        assert_equal expected, r.within_window?(at), "#{hour}h should be #{expected}"
      end
      # A normal same-day window still behaves.
      day = build_reward(schedule: { "windows" => [{ "days" => [], "from_hour" => 9, "to_hour" => 17 }] })
      assert day.within_window?(Time.zone.now.change(hour: 12))
      refute day.within_window?(Time.zone.now.change(hour: 20))
    end
  end

  # expires_at is the fixed date every issued voucher dies on. Set in the past,
  # the offer still read as :open and each redemption spent points on a voucher
  # that was already expired when it was created.
  test "a fixed voucher expiry in the past is refused, and never reads as open" do
    r = build_reward(expires_at: 3.days.ago)
    refute r.valid?
    assert_includes r.errors.attribute_names, :expires_at

    # A reward whose date has since passed stays editable, but stops offering.
    ActsAsTenant.with_tenant(@ws) do
      saved = build_reward(expires_at: 2.days.from_now)
      saved.save!
      saved.update_column(:expires_at, 1.day.ago)
      assert_equal :ended, saved.reload.redeem_state
      refute saved.available?
      assert saved.update(active: false), "an elapsed reward can still be edited"
    end
  end

  test "an availability window that ends before it starts is refused" do
    r = build_reward(starts_at: 10.days.from_now, ends_at: 2.days.from_now)
    refute r.valid?
    assert_includes r.errors.attribute_names, :ends_at
  end

  test "stock cannot go negative" do
    refute build_reward(stock: -4).valid?
    assert build_reward(stock: 0).valid?, "zero is a legitimate 'stop issuing'"
    assert build_reward(stock: nil).valid?, "nil is unlimited"
  end

  # Cutting stock below what has already gone out stops further issuing without
  # touching the vouchers customers already hold.
  test "lowering stock below what was issued stops issuing but keeps issued vouchers" do
    ActsAsTenant.with_tenant(@ws) do
      r = build_reward(stock: 5)
      r.save!
      3.times { assert r.claim_stock! }
      assert_equal 2, r.reload.remaining

      assert r.update(stock: 1)
      assert_equal 0, r.reload.remaining
      refute r.in_stock?
      refute r.claim_stock!, "no further units go out"
      assert_equal 3, r.reload.redeemed_count, "already-issued vouchers are untouched"

      # Restocking works the obvious way.
      assert r.update(stock: 6)
      assert_equal 3, r.reload.remaining
      assert r.claim_stock!
    end
  end

  # The list is the "kho quà" screen: which offers have run out is the question
  # it exists to answer, and an exhausted reward used to look identical to a
  # healthy one — green "Đang bật" chip, a quiet "0 lượt", nothing else.
  test "the list marks rewards that have run out or cannot be redeemed" do
    ActsAsTenant.with_tenant(@ws) do
      sold_out = build_reward(title: "Hết hàng", stock: 2); sold_out.save!
      2.times { sold_out.claim_stock! }
      low = build_reward(title: "Sắp hết", stock: 6); low.save!
      3.times { low.claim_stock! }
      build_reward(title: "Còn nhiều", stock: 100).save!
      build_reward(title: "Ngoài giờ",
                   schedule: { "windows" => [{ "days" => [], "from_hour" => 3, "to_hour" => 4 }] }).save!
    end

    get merchant_rewards_path
    assert_response :success
    assert_match I18n.t("merchant.rewards.state_out_of_stock"), response.body
    assert_match I18n.t("merchant.rewards.state_closed"), response.body
    # "Còn nhiều" must not be flagged.
    assert_equal 1, response.body.scan(I18n.t("merchant.rewards.state_out_of_stock")).size
  end

  # Each card ran two voucher COUNTs of its own, so the page cost two queries
  # per reward on top of everything else.
  test "the list counts vouchers without a query per card" do
    ActsAsTenant.with_tenant(@ws) do
      6.times { |i| build_reward(title: "Ưu đãi #{i}").save! }
    end
    counts = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, p|
      counts += 1 if p[:sql].to_s.include?('FROM "vouchers"')
    end
    get merchant_rewards_path
    ActiveSupport::Notifications.unsubscribe(sub)
    assert_response :success
    assert counts <= 2, "expected one grouped count per metric, got #{counts} voucher queries"
  end

  # Both of these wrote with the return value dropped, so a refused save still
  # reported success.
  test "toggling a reward that cannot be saved does not report success" do
    r = ActsAsTenant.with_tenant(@ws) { build_reward.tap(&:save!) }
    r.update_column(:title, "")

    patch toggle_merchant_reward_path(r)
    assert_redirected_to merchant_rewards_path
    assert_nil flash[:notice]
    assert flash[:alert].present?
    assert r.reload.active?, "still on — nothing was saved"
  end
end
