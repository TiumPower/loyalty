require "test_helper"

# Manual point adjustment writes straight to the ledger with no purchase behind
# it — the one place a shop can create or destroy what it owes a customer.
class PointsAdjustmentTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "adjust")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      @membership = Membership.create!(user: @user, workspace: @ws, role: "manager")
      @member = create(:member, workspace: @ws)
      @member.point_transactions.create!(workspace: @ws, kind: "earn", amount: 500)
      @member.recompute_points!
    end
    sign_in @user
  end

  def adjust(amount, note: "Đền bù đồ uống lỗi")
    post "/merchant/customers/#{@member.id}/adjust", params: { amount: amount, note: note }
  end

  def balance = @member.reload.points_balance

  test "a normal comp is credited and attributed to the staff who did it" do
    adjust("100")
    assert_equal 600, balance
    tx = ActsAsTenant.with_tenant(@ws) { PointTransaction.where(member_id: @member.id, kind: "adjust").last }
    assert_equal @user.id, tx.staff_id
    assert_equal "Đền bù đồ uống lỗi", tx.note
  end

  test "a deduction within the balance works" do
    adjust("-200")
    assert_equal 300, balance
  end

  # Deducting more than the customer holds used to leave them on a negative
  # balance, which every tier, redemption and expiry calculation then ran on.
  test "the balance can never be driven negative" do
    adjust("-501") # one more than they hold, and within the per-adjustment ceiling
    assert_equal 500, balance, "the customer was left owing the shop points"
    assert_match(/không thể trừ nhiều hơn/i, flash[:alert].to_s)
  end

  test "an implausible deduction is refused by the ceiling before anything else" do
    adjust("-99999999")
    assert_equal 500, balance
  end

  test "deducting exactly the balance is allowed and lands on zero" do
    adjust("-500")
    assert_equal 0, balance
  end

  # One stray keystroke on a 50-point comp used to mint fifty million.
  test "an implausible amount is refused" do
    adjust("50000000")
    assert_equal 500, balance
    assert_match(/vượt giới hạn/i, flash[:alert].to_s)
  end

  test "the per-adjustment ceiling itself is allowed" do
    adjust(Merchant::CustomersController::MAX_ADJUST.to_s)
    assert_equal 500 + Merchant::CustomersController::MAX_ADJUST, balance
  end

  test "an adjustment with no reason is refused" do
    assert_no_difference -> { ActsAsTenant.with_tenant(@ws) { PointTransaction.where(member_id: @member.id).count } } do
      adjust("100", note: "")
    end
    assert_match(/lý do/i, flash[:alert].to_s)
  end

  test "zero is refused" do
    adjust("0")
    assert_equal 500, balance
  end

  test "a staff member cannot adjust points at all" do
    ActsAsTenant.with_tenant(@ws) { @membership.update!(role: "staff") }
    adjust("100")
    assert_equal 500, balance
  end

  test "a customer from another shop is not reachable" do
    other_ws = create(:workspace, subdomain: "other")
    other = ActsAsTenant.with_tenant(other_ws) { create(:member, workspace: other_ws) }

    post "/merchant/customers/#{other.id}/adjust", params: { amount: "100", note: "x" }
    assert_response :not_found
    assert_equal 0, other.reload.points_balance
  end
end

# The shop's customer database: filters, search and tenant isolation.
class CustomersListTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "custlist")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @a = create(:member, workspace: @ws, name: "Nguyễn An", email: "an@example.com", phone: "0901111111")
      @b = create(:member, workspace: @ws, name: "Trần Bình", email: "binh@example.com", phone: "0902222222")
    end
    sign_in @user
  end

  test "lists the shop's customers" do
    get "/merchant/customers"
    assert_response :success
    assert_match "Nguyễn An", response.body
    assert_match "Trần Bình", response.body
  end

  test "never shows another shop's customers" do
    other_ws = create(:workspace, subdomain: "othershop")
    ActsAsTenant.with_tenant(other_ws) { create(:member, workspace: other_ws, name: "Người Lạ") }

    get "/merchant/customers"
    assert_no_match(/Người Lạ/, response.body)
  end

  test "search finds by name, email and phone" do
    { "Bình" => "Trần Bình", "an@example" => "Nguyễn An", "0902222222" => "Trần Bình" }.each do |query, expected|
      get "/merchant/customers", params: { q: query }
      assert_response :success
      assert_match expected, response.body, "searching #{query.inspect} did not find #{expected}"
    end
  end

  test "the tier column shows the shop's own tier names, not the internal key" do
    tier = ActsAsTenant.with_tenant(@ws) { @ws.tiers.ordered.first }
    skip "no tiers seeded" if tier.nil?
    ActsAsTenant.with_tenant(@ws) { @a.update_columns(tier_key: tier.key) }

    get "/merchant/customers"
    assert_match tier.name, response.body
    assert_no_match(/>#{tier.key.capitalize}</, response.body, "still printing the raw key")
  end

  test "a customer detail page renders" do
    get "/merchant/customers/#{@a.id}"
    assert_response :success
    assert_match "Nguyễn An", response.body
  end

  test "another shop's customer detail is not reachable" do
    other_ws = create(:workspace, subdomain: "othershop2")
    other = ActsAsTenant.with_tenant(other_ws) { create(:member, workspace: other_ws) }

    get "/merchant/customers/#{other.id}"
    assert_response :not_found
  end
end
