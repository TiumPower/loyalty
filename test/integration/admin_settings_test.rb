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
end
