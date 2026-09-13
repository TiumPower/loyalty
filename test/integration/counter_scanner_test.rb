require "test_helper"

# The counter scanner is the most-used screen in the product and the one that
# hands out money. A second tap must never award a second time.
class CounterScannerTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "scansmoke")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000,
                               tiers_enabled: false)
      @member = create(:member, workspace: @ws)
    end
    sign_in @user
  end

  def award(key:, amount: 100_000)
    post "/merchant/earn", params: { member_id: @member.id, amount: amount, earn_key: key }
  end

  def purchases = Purchase.unscoped.where(workspace_id: @ws.id)

  test "a bill awards points once" do
    assert_difference -> { purchases.count }, 1 do
      award(key: "abc-123")
    end
    assert_equal 10, @member.reload.points_balance
  end

  test "submitting the same scan twice does not pay twice" do
    award(key: "abc-123")
    assert_no_difference -> { purchases.count } do
      award(key: "abc-123")
    end
    assert_equal 10, @member.reload.points_balance, "the customer was paid twice"
    assert_response :success, "the replay should still show the cashier a result"
  end

  test "correcting a rejected amount still awards only once" do
    post "/merchant/earn", params: { member_id: @member.id, amount: "0", earn_key: "k1" }
    assert_response :unprocessable_entity
    assert_equal 0, purchases.count

    award(key: "k1", amount: 50_000)
    assert_equal 1, purchases.count
    assert_equal 5, @member.reload.points_balance
  end

  test "two genuinely separate scans both award" do
    award(key: "scan-1")
    award(key: "scan-2")
    assert_equal 2, purchases.count
    assert_equal 20, @member.reload.points_balance
  end

  test "a bill of zero is refused" do
    assert_no_difference -> { purchases.count } do
      post "/merchant/earn", params: { member_id: @member.id, amount: "0", earn_key: "z" }
    end
    assert_response :unprocessable_entity
  end

  test "a customer can be looked up by phone as well as by email" do
    ActsAsTenant.with_tenant(@ws) do
      @member.update!(email: "khach@example.com", phone: "0912345678")
    end

    post "/merchant/earn/lookup", params: { q: "khach@example.com" }
    assert_response :success
    assert_match @member.display_name, response.body

    post "/merchant/earn/lookup", params: { q: "0912 345 678" }
    assert_response :success
    assert_match @member.display_name, response.body, "a phone number should find the same customer"
  end

  test "an unknown lookup says so rather than erroring" do
    post "/merchant/earn/lookup", params: { q: "0000000000" }
    assert_response :unprocessable_entity
    assert_match(/không tìm thấy/i, response.body)
  end

  test "an unknown member is refused" do
    assert_no_difference -> { purchases.count } do
      post "/merchant/earn", params: { member_id: 0, amount: 100_000, earn_key: "x" }
    end
    assert_response :unprocessable_entity
  end

  # --- Redeeming a voucher at the counter ---------------------------------

  def make_voucher
    ActsAsTenant.with_tenant(@ws) do
      reward = Reward.create!(workspace: @ws, title: "Cà phê", kind: "voucher",
                              cost_points: 100, value_unit: "item")
      Voucher.create!(workspace: @ws, member: @member, reward: reward, state: "active",
                      redeem_token: "1234567890", redeem_token_expires_at: 10.minutes.from_now)
    end
  end

  test "a voucher is consumed once and only once" do
    v = make_voucher

    post "/merchant/redeem", params: { voucher_id: v.id }
    assert_response :success
    assert_equal "used", v.reload.state
    first_used_at = v.used_at

    # Second tap on the same confirm button.
    post "/merchant/redeem", params: { voucher_id: v.id }
    assert_response :success
    assert_equal first_used_at.to_i, v.reload.used_at.to_i, "the voucher was consumed twice"
    assert_match(/đã dùng|đã sử dụng/i, response.body)
  end

  test "mark_used! reports whether this caller is the one that consumed it" do
    v = make_voucher
    assert v.mark_used!(outlet: nil, staff: nil), "first call should claim it"
    assert_not v.mark_used!(outlet: nil, staff: nil), "second call must not claim it again"
  end

  test "an expired use code is refused" do
    v = make_voucher
    v.update!(redeem_token_expires_at: 1.minute.ago)

    post "/merchant/redeem/lookup", params: { token: "1234567890" }
    assert_response :unprocessable_entity
    assert_equal "active", v.reload.state
  end

  test "scanning a member QR on the redeem tab still gets an idempotency key" do
    ActsAsTenant.with_tenant(@ws) { @member.update!(email: "qr@example.com") }
    token = MemberQr.encode(@member)

    post "/merchant/redeem/lookup", params: { token: token }
    assert_response :success
    assert_match(/name="earn_key" value="[0-9a-f-]{36}"/, response.body,
                 "the earn form rendered from the redeem tab had no key")
  end
end
