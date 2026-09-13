require "test_helper"

# Points are a liability the shop owes its customers. Expiring the wrong ones —
# or expiring points a customer already spent — is money taken back by mistake.
class ExpirePointsTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace)
    ActsAsTenant.current_tenant = @ws
    @program = create(:loyalty_program, workspace: @ws, points_expiry_months: 6)
    @member = create(:member, workspace: @ws)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  NO_EXPIRY = Object.new

  def credit(amount, at:, expires_at: NO_EXPIRY)
    exp = expires_at.equal?(NO_EXPIRY) ? at + 6.months : expires_at
    tx = @member.point_transactions.create!(workspace: @ws, kind: "earn", amount: amount,
                                            expires_at: exp)
    tx.update_columns(created_at: at)
    tx
  end

  def debit(amount, at: Time.current)
    tx = @member.point_transactions.create!(workspace: @ws, kind: "redeem", amount: -amount)
    tx.update_columns(created_at: at)
    tx
  end

  test "expires only the lots whose date has passed" do
    credit(100, at: 10.months.ago, expires_at: 4.months.ago)  # lapsed
    credit(50,  at: 1.month.ago)                              # still good
    @member.recompute_points!

    assert_equal 100, @member.expirable_points
    assert_equal 100, ExpirePoints.expire_member(@member)
    assert_equal 50, @member.reload.points_balance
  end

  test "points already spent are not expired a second time" do
    credit(100, at: 10.months.ago, expires_at: 4.months.ago)
    credit(50,  at: 1.month.ago)
    debit(100, at: 2.months.ago) # the customer already spent the old lot
    @member.recompute_points!

    assert_equal 0, @member.expirable_points, "the lapsed lot was already redeemed"
    assert_equal 0, ExpirePoints.expire_member(@member)
    assert_equal 50, @member.reload.points_balance
  end

  test "a partial redemption leaves only the remainder to expire" do
    credit(100, at: 10.months.ago, expires_at: 4.months.ago)
    debit(30, at: 5.months.ago)
    @member.recompute_points!

    assert_equal 70, @member.expirable_points
    ExpirePoints.expire_member(@member)
    assert_equal 0, @member.reload.points_balance
  end

  test "nothing expires for a shop that never switched expiry on" do
    @program.update!(points_expiry_months: 0)
    credit(100, at: 10.months.ago, expires_at: nil)
    @member.recompute_points!

    assert_equal 0, @member.expirable_points
    assert_equal 100, @member.reload.points_balance
    ExpirePoints.run
    assert_equal 100, @member.reload.points_balance
  end

  test "warns once about points expiring soon, then stays quiet" do
    credit(80, at: 1.day.ago, expires_at: 3.days.from_now)
    @member.recompute_points!

    amount, date = @member.points_expiring_soon(within: 7.days)
    assert_equal 80, amount
    assert_not_nil date

    assert_difference -> { @member.notifications.count }, 1 do
      ExpirePoints.remind_member(@member)
      ExpirePoints.remind_member(@member)
    end
  end

  test "a lot with no expiry date never lapses" do
    credit(100, at: 3.years.ago, expires_at: nil)
    @member.recompute_points!
    assert_equal 0, @member.expirable_points
  end
end
