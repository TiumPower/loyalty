require "test_helper"

class ShopPickerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @a = create(:workspace, name: "Quán A", subdomain: "quana")
    @b = create(:workspace, name: "Quán B", subdomain: "quanb")
    [@a, @b].each { |w| ActsAsTenant.with_tenant(w) { Membership.create!(user: @user, workspace: w, role: "owner") } }
    sign_in @user
  end

  test "lists only the shops this user belongs to" do
    outsider = create(:workspace, name: "Không phải của tôi", subdomain: "nguoila")
    get "/merchant/choose"
    assert_response :success
    assert_match "Quán A", response.body
    assert_match "Quán B", response.body
    assert_no_match(/Không phải của tôi/, response.body)
    assert_no_match(/nguoila/, response.body)
  end

  test "one shop needs no choosing" do
    ActsAsTenant.with_tenant(@b) { Membership.where(user: @user, workspace: @b).destroy_all }
    get "/merchant/choose"
    assert_response :redirect
  end

  test "switching to one of your own shops works" do
    post "/merchant/switch_workspace/#{@b.id}"
    assert_response :redirect
    assert_equal @b.id, session[:workspace_id]
  end

  test "switching to someone else's shop is refused, and says so" do
    outsider = create(:workspace, subdomain: "nguoila")
    post "/merchant/switch_workspace/#{outsider.id}"
    assert_redirected_to "/merchant/choose"
    assert_match(/không có quyền/i, flash[:alert].to_s)
    assert_not_equal outsider.id, session[:workspace_id]
  end

  test "a made-up id is refused rather than exploding" do
    post "/merchant/switch_workspace/999999"
    assert_redirected_to "/merchant/choose"
  end
end

class MerchantAccountTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "acct")
    @user = create(:user, password: "old-password")
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: @user, workspace: @ws, role: "owner") }
    sign_in @user
  end

  test "renders" do
    get "/merchant/account"
    assert_response :success
  end

  test "the display name can be changed" do
    patch "/merchant/account", params: { user: { name: "Tên Mới" } }
    assert_equal "Tên Mới", @user.reload.name
  end

  test "changing the password requires the current one" do
    patch "/merchant/account", params: {
      user: { current_password: "wrong", password: "brand-new-pass", password_confirmation: "brand-new-pass" }
    }
    assert_response :unprocessable_entity
    assert @user.reload.valid_password?("old-password"), "the password changed without the current one"
  end

  test "the right current password changes it and keeps the session" do
    patch "/merchant/account", params: {
      user: { current_password: "old-password", password: "brand-new-pass", password_confirmation: "brand-new-pass" }
    }
    assert_response :redirect
    assert @user.reload.valid_password?("brand-new-pass")

    get "/merchant/account"
    assert_response :success, "the owner was signed out by their own password change"
  end

  test "the account page offers a way to sign out" do
    get "/merchant/account"
    assert_select "form[action=?]", "/merchant/logout"
  end

  test "the quick-login QR says what scanning it does" do
    get "/merchant/account"
    assert_match(/#{(StaffLogin::TTL / 60).to_i} phút/, response.body)
    assert_match(/đăng nhập vào tài khoản của bạn/i, response.body)
  end
end
