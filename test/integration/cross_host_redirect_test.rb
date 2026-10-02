require "test_helper"

# Every shop's dashboard and PWA live on their own subdomain, so this app
# redirects across hosts as a matter of course. Rails refuses that unless asked
# — and the one caller that cannot be asked is Devise, which bounces an
# already-signed-in merchant off /merchant/login by calling
# after_sign_in_path_for and redirecting to whatever comes back.
#
# In production that is a subdomain URL, so "bạn đã đăng nhập rồi" arrived as a
# 500 on the login page. The guard is production-only
# (force_subdomain_links?), which is exactly why no test saw it; these force it
# on.
class CrossHostRedirectTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace, subdomain: "cozycafe")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: @user, workspace: @ws, role: "owner") }
  end

  test "a signed-in merchant opening the login page is sent to their shop, not a 500" do
    sign_in @user
    across_hosts { get "/merchant/login" }
    assert_response :redirect
    assert_equal "https://cozycafe.#{ApplicationController::PLATFORM_HOST}/merchant",
                 response.location
  end

  test "the password screens bounce the same way" do
    sign_in @user
    across_hosts { get "/merchant/password/new" }
    assert_response :redirect
    assert_match "cozycafe.#{ApplicationController::PLATFORM_HOST}", response.location
  end

  # The point of raise_on_open_redirects is to stop somewhere else sending our
  # users away, and widening it to our own hosts must not widen it to anyone
  # else's. `redirect_to` only sets allow_other_host when own_host_url? says
  # yes, so a false here is Rails' own refusal left intact.
  test "a host that merely starts with ours is not ours" do
    c = ApplicationController.new
    base = ApplicationController::PLATFORM_HOST
    assert c.send(:own_host_url?, "https://#{base}/merchant")
    assert c.send(:own_host_url?, "https://shop.#{base}/merchant")
    refute c.send(:own_host_url?, "https://#{base}.evil.example/steal")
    refute c.send(:own_host_url?, "https://evil.example/#{base}")
    refute c.send(:own_host_url?, "https://not#{base}/x")
    refute c.send(:own_host_url?, "/merchant"), "a path is same-host anyway"
    refute c.send(:own_host_url?, "javascript:alert(1)")
  end
end
