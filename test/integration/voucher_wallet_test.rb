require "test_helper"

# The wallet is where a customer keeps things they already paid points for, and
# the counter flow is what turns one into a free coffee. Both sides matter.
class VoucherWalletTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace, subdomain: "walletws")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @staff = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000)
      @ws.memberships.create!(user: @staff, role: "staff")
      @member = create(:member, workspace: @ws, email: "wallet@example.com")
      @reward = create(:reward, workspace: @ws, cost_points: 100, valid_days: 30)
    end
  end

  def voucher(attrs = {})
    ActsAsTenant.with_tenant(@ws) do
      Voucher.create!({ workspace: @ws, member: @member, reward: @reward, source: "redeem",
                        state: "active", points_spent: 100, expires_at: 20.days.from_now }.merge(attrs))
    end
  end

  def sign_in_member!
    base = "/w/#{@ws.slug}"
    post "#{base}/login", params: { email: @member.email }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email, purpose: "login").order(:id).last
    post "#{base}/verify", params: { code: ch.code }
  end

  # Step 1 of the counter flow verifies the customer's one-time code. Step 2 took
  # a bare voucher_id, so the code — the entire proof that the customer is
  # standing there and agreed — could be skipped by posting an id. Any staff
  # login could burn any customer's voucher in the shop.
  test "a voucher cannot be consumed without a live use code" do
    v = voucher
    assert_nil v.redeem_token, "no code has been started"

    sign_in @staff
    post merchant_redeem_path, params: { voucher_id: v.id }
    assert_response :unprocessable_entity
    assert_equal "active", v.reload.state, "the customer still holds it"
  end

  # The same hole with a code that has lapsed: lookup refuses it, so step 2
  # must too.
  test "a lapsed use code cannot be confirmed" do
    v = voucher
    ActsAsTenant.with_tenant(@ws) { v.start_use! }
    token = v.reload.redeem_token
    v.update_column(:redeem_token_expires_at, 1.minute.ago)

    sign_in @staff
    post merchant_redeem_path, params: { voucher_id: v.id, token: token }
    assert_response :unprocessable_entity
    assert_equal "active", v.reload.state
  end

  test "the real counter flow still works end to end" do
    v = voucher
    ActsAsTenant.with_tenant(@ws) { v.start_use! }
    token = v.reload.redeem_token

    sign_in @staff
    post merchant_redeem_lookup_path, params: { token: token }
    assert_response :success
    # The confirm form has to carry the verified code forward.
    assert_select "input[name=token][value=?]", token

    post merchant_redeem_path, params: { voucher_id: v.id, token: token }
    assert_response :success
    assert_equal "used", v.reload.state
    assert_equal @staff.id, v.used_by_staff_id
  end

  # A voucher whose own expiry has passed but which the nightly sweep has not
  # flipped to "expired" yet must not still be redeemable at the counter.
  test "a voucher past its expiry cannot be redeemed even before the sweep" do
    v = voucher
    ActsAsTenant.with_tenant(@ws) { v.start_use! }
    token = v.reload.redeem_token
    v.update_column(:expires_at, 1.hour.ago)
    assert_equal "active", v.reload.state, "not swept yet"

    sign_in @staff
    post merchant_redeem_path, params: { voucher_id: v.id, token: token }
    assert_response :unprocessable_entity
    assert_equal "active", v.reload.state
  end

  # The "Đã đổi" tab listed every voucher the member had ever held, newest
  # first, so the two they can actually use sat wherever they happened to fall
  # among a year of used and expired ones — under a tab badge promising "2".
  test "the owned tab puts usable vouchers first" do
    old_used = voucher(state: "used", created_at: 2.days.ago)
    old_exp  = voucher(expires_at: 3.days.ago, created_at: 1.day.ago)
    usable   = voucher(created_at: 10.days.ago)

    sign_in_member!
    get "/w/#{@ws.slug}/wallet"
    assert_response :success

    body = response.body
    assert body.index(usable.code) < body.index(old_used.code), "usable before used"
    assert body.index(usable.code) < body.index(old_exp.code), "usable before expired"
  end

  # Capping the list by recency would have hidden a long-dated voucher the
  # member can still use behind a wall of newer, finished ones.
  test "a usable voucher is never dropped by the history cap" do
    old_usable = voucher(created_at: 3.years.ago, expires_at: 60.days.from_now)
    (Customer::WalletController::MAX_VOUCHERS + 10).times do |i|
      voucher(state: "used", created_at: i.hours.ago, used_at: i.hours.ago)
    end

    sign_in_member!
    get "/w/#{@ws.slug}/wallet"
    assert_response :success
    assert_match old_usable.code, response.body
    assert_equal old_usable.code,
                 response.body.scan(/[A-Z0-9]{6,}/).find { |c| c == old_usable.code }
  end
end
