require "test_helper"

# Branch history (purchases, points, ratings) is protected by foreign keys.
# The app must say so rather than letting the database raise a 500.
class OutletDeletionTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "outletsmoke")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @outlet = Outlet.create!(workspace: @ws, name: "Chi nhánh 1", code: "CN1")
      @member = create(:member, workspace: @ws)
    end
    sign_in @user
  end

  test "a branch that never traded can be deleted" do
    assert_difference -> { Outlet.unscoped.where(workspace_id: @ws.id).count }, -1 do
      delete "/merchant/outlets/#{@outlet.id}"
    end
  end

  test "a branch with purchases is kept, with an explanation" do
    ActsAsTenant.with_tenant(@ws) do
      Purchase.create!(workspace: @ws, member: @member, outlet: @outlet, amount: 50_000, points_earned: 5)
    end

    assert_no_difference -> { Outlet.unscoped.where(workspace_id: @ws.id).count } do
      delete "/merchant/outlets/#{@outlet.id}"
    end
    assert_match(/không xoá được/i, flash[:alert].to_s)
    assert_match(/tắt hoạt động/i, flash[:alert].to_s)
  end

  test "the branch can still be deactivated instead" do
    ActsAsTenant.with_tenant(@ws) do
      Purchase.create!(workspace: @ws, member: @member, outlet: @outlet, amount: 50_000, points_earned: 5)
    end
    patch "/merchant/outlets/#{@outlet.id}", params: { outlet: { active: "0" } }
    assert_not @outlet.reload.active?
  end
end
