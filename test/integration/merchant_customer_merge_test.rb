require "test_helper"

# The owner-facing side of merging duplicates: who is allowed to do it, and that
# the confirmation screen tells the truth about what will move.
class MerchantCustomerMergeTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "mergeui")
    @owner = create(:user)
    @staff = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      @ws.memberships.create!(user: @owner, role: "owner")
      @ws.memberships.create!(user: @staff, role: "staff")
      @keeper = create(:member, workspace: @ws, name: "Chị Lan", email: "lan@example.com")
      @dupe   = create(:member, workspace: @ws, name: "Chị Lan", email: nil, phone: "0901234567")
      @dupe.point_transactions.create!(workspace: @ws, kind: "earn", amount: 300)
      @dupe.recompute_points!
    end
  end

  # Merging destroys a profile, so it belongs behind the same gate as deleting
  # one — not with the staff who adjust points.
  test "staff cannot reach the merge screen" do
    sign_in @staff
    get merge_merchant_customer_path(@keeper)
    assert_response :redirect
  end

  test "staff cannot perform a merge" do
    sign_in @staff
    post merge_into_merchant_customer_path(@keeper, with: @dupe.id)
    assert_response :redirect
    assert ActsAsTenant.with_tenant(@ws) { Member.exists?(@dupe.id) }, "the profile must still be there"
  end

  test "the owner is offered the same-named profile as a candidate" do
    sign_in @owner
    get merge_merchant_customer_path(@keeper)
    assert_response :success
    assert_match "0901234567", response.body
  end

  test "the confirmation screen says what will move" do
    sign_in @owner
    get merge_merchant_customer_path(@keeper, with: @dupe.id)
    assert_response :success
    assert_match(/điểm giao dịch/, response.body)
    # And that the survivor gains the phone, which is the point of the merge.
    assert_match(/0901234567/, response.body)
  end

  test "the owner merges and the points land on the surviving profile" do
    sign_in @owner
    post merge_into_merchant_customer_path(@keeper, with: @dupe.id)
    assert_redirected_to merchant_customer_path(@keeper)

    ActsAsTenant.with_tenant(@ws) do
      assert_not Member.exists?(@dupe.id)
      @keeper.reload
      assert_equal 300, @keeper.points_balance
      assert_equal "0901234567", @keeper.phone
    end
  end

  test "merging with no profile chosen is refused rather than guessed at" do
    sign_in @owner
    post merge_into_merchant_customer_path(@keeper)
    assert_redirected_to merge_merchant_customer_path(@keeper)
    assert ActsAsTenant.with_tenant(@ws) { Member.exists?(@dupe.id) }
  end
end
