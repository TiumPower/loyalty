require "test_helper"

# The platform OTP switch: it makes every member account reachable by anyone who
# knows the email, so it must be off by default and visible while it is on.
class AdminSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:admin_user)
    sign_in @admin, scope: :admin_user
  end

  test "the switch is off until it is turned on" do
    assert_not AppSetting.show_otp?
    get "/admin/settings"
    assert_response :success
  end

  test "turning it on and off again writes the platform flag" do
    patch "/admin/settings", params: { show_otp: "true" }
    assert AppSetting.show_otp?

    patch "/admin/settings", params: { show_otp: "false" }
    assert_not AppSetting.show_otp?
  end

  test "every admin page warns while the switch is on" do
    AppSetting.set_flag(AppSetting::SHOW_OTP_KEY, true)
    get "/admin"
    assert_response :success
    assert_match(/hiện mã OTP/i, response.body)
  end

  # ---- Zalo OTP gateway panel ---------------------------------------------

  test "the settings screen reports the gateway as unconfigured" do
    get "/admin/settings"
    assert_response :success
    assert_match(/Cổng gửi OTP qua Zalo/, response.body)
    assert_match(/Chưa cấu hình/, response.body)
  end

  # The refresh token rotates, so the one in .env goes stale; pasting a new one
  # must not need a deploy. Storing it also has to invalidate the cached access
  # token, or the next send keeps using the old pair.
  test "pasting a refresh token stores it and forces a refresh" do
    AppSetting.set("zns_access_token", "stale")
    patch "/admin/settings/otp-gateway", params: { zns_refresh_token: "  fresh-token " }
    assert_redirected_to "/admin/settings"
    assert_equal "fresh-token", AppSetting.get("zns_refresh_token")
    assert_equal "", AppSetting.get("zns_access_token")
  end

  test "an empty refresh token is rejected rather than stored" do
    AppSetting.set("zns_refresh_token", "keep-me")
    patch "/admin/settings/otp-gateway", params: { zns_refresh_token: "" }
    assert_equal "keep-me", AppSetting.get("zns_refresh_token")
  end

  test "a test send to a malformed number fails without calling a provider" do
    post "/admin/settings/otp-test", params: { phone: "12" }
    assert_redirected_to "/admin/settings"
    assert_match(/bad_phone/, flash[:alert])
  end

  test "a test send with no provider configured says so instead of pretending" do
    post "/admin/settings/otp-test", params: { phone: "0901234567" }
    assert_redirected_to "/admin/settings"
    assert_match(/not_configured/, flash[:alert])
  end
end
