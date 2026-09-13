require "test_helper"

# Request-level behaviour of undo. The service itself is covered in
# test/services/void_purchase_test.rb; these are the cases it does not reach.
class VoidPurchaseRequestTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "voidtest")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      @membership = Membership.create!(user: @user, workspace: @ws, role: "manager")
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000, tiers_enabled: false)
      @member = create(:member, workspace: @ws)
      @purchase = EarnPoints.new(member: @member, amount: 1_000_000, staff: @user).call.purchase # +100
    end
  end

  def balance = @member.reload.points_balance
  def undo(purchase = @purchase, reason: "bấm nhầm")
    post "/merchant/purchases/#{purchase.id}/void", params: { reason: reason }
  end

  # The customer may have already spent these points on a reward, which this
  # service deliberately never claws back. Reversing the full amount used to
  # leave them on a negative balance.
  test "a customer who already spent the points is not left owing the shop" do
    ActsAsTenant.with_tenant(@ws) do
      @member.point_transactions.create!(workspace: @ws, kind: "redeem", amount: -100)
      @member.recompute_points!
    end
    assert_equal 0, balance

    sign_in @user
    undo
    assert_equal 0, balance, "the customer was left on a negative balance"
    assert @purchase.reload.voided?, "the bill should still be voided so revenue is corrected"
    assert_match(/không thu hồi được/i, flash[:notice].to_s)
  end

  test "a partial spend reverses only what is left" do
    ActsAsTenant.with_tenant(@ws) do
      @member.point_transactions.create!(workspace: @ws, kind: "redeem", amount: -70)
      @member.recompute_points!
    end
    assert_equal 30, balance

    sign_in @user
    undo
    assert_equal 0, balance
  end

  test "undoing twice does not deduct twice, and says it was already undone" do
    sign_in @user
    undo
    assert_equal 0, balance
    undo
    assert_equal 0, balance
    # Used to report a permission error, which is both wrong and alarming.
    assert_match(/đã được huỷ/i, flash[:alert].to_s)
    assert_no_match(/không có quyền/i, flash[:alert].to_s)
  end

  test "another shop's bill cannot be undone" do
    other = create(:workspace, subdomain: "othervoid")
    foreign = ActsAsTenant.with_tenant(other) do
      create(:loyalty_program, workspace: other, earn_points: 1, earn_per_amount: 10_000, tiers_enabled: false)
      EarnPoints.new(member: create(:member, workspace: other), amount: 500_000).call.purchase
    end

    sign_in @user
    post "/merchant/purchases/#{foreign.id}/void", params: { reason: "x" }
    assert_response :not_found
    assert_not foreign.reload.voided?
  end

end
