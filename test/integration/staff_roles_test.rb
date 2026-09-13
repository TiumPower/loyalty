require "test_helper"

# A shop must never be able to strip itself of everyone who can administer it.
class StaffRolesTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "staffsmoke")
    @owner = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      @owner_m = Membership.create!(user: @owner, workspace: @ws, role: "owner")
    end
    sign_in @owner
  end

  test "the only owner cannot demote themselves" do
    patch "/merchant/staff/#{@owner_m.id}", params: { role: "cashier" }
    assert_equal "owner", @owner_m.reload.role
    assert_match(/duy nhất/, flash[:alert].to_s)
  end

  test "the only owner cannot be removed" do
    assert_no_difference -> { Membership.where(workspace_id: @ws.id).count } do
      delete "/merchant/staff/#{@owner_m.id}"
    end
    assert_equal "owner", @owner_m.reload.role
  end

  test "an owner can step down once another owner exists" do
    other = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: other, workspace: @ws, role: "owner") }

    patch "/merchant/staff/#{@owner_m.id}", params: { role: "manager" }
    assert_equal "manager", @owner_m.reload.role
  end

  test "a made-up role is rejected" do
    patch "/merchant/staff/#{@owner_m.id}", params: { role: "superuser" }
    assert_equal "owner", @owner_m.reload.role
  end

  test "the shop always keeps someone who can manage it" do
    ActsAsTenant.with_tenant(@ws) do
      staff = Membership.create!(user: create(:user), workspace: @ws, role: "staff")
      patch "/merchant/staff/#{staff.id}", params: { role: "cashier" }
      assert_equal "cashier", staff.reload.role
      assert Membership.where(workspace_id: @ws.id).any?(&:can_manage?), "no one left who can manage"
    end
  end
end
