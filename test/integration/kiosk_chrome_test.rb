require "test_helper"

# The staff launcher is its own little app. Screens reached from it must keep the
# kiosk chrome rather than dropping a cashier into the full admin, whose menu
# drawer gives them the whole back office.
class KioskChromeTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "kiosk")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: @user, workspace: @ws, role: "owner") }
    sign_in @user
  end

  test "transactions opened from the launcher have no admin sidebar" do
    get "/merchant/transactions?kiosk=1"
    assert_response :success
    # The theme <style> block mentions .l-side, so match the element itself.
    assert_no_match(/<aside[^>]*class="l-side/, response.body, "kiosk view should not render the admin sidebar")
    assert_match "/merchant/scan-home", response.body, "kiosk view needs a way back"
  end

  test "transactions opened normally keep the admin sidebar" do
    get "/merchant/transactions"
    assert_response :success
    assert_match(/<aside[^>]*class="l-side/, response.body)
  end

  # Filtering from the kiosk must not bounce the cashier into the full admin.
  test "the kiosk flag survives the filter form" do
    get "/merchant/transactions?kiosk=1"
    assert_match(/name="kiosk"/, response.body)
  end
end
