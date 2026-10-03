require "test_helper"

# Bảng Tự động hoá trước đây chỉ in trạng thái "Bật"/"Tắt" như một dòng chữ,
# còn công tắc thật nằm trong trang Chỉnh sửa — nhìn vào bảng không biết bật ở
# đâu.
class AutomationToggleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace, subdomain: "auto")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @reward = create(:reward, workspace: @ws)
    end
    sign_in @user
  end

  def autos = @ws.reload.settings.fetch("automations", {})

  test "bật tắt ngay từ danh sách" do
    @ws.update!(settings: @ws.settings.merge(
      "automations" => { "welcome" => { "enabled" => false, "reward_id" => @reward.id } }))

    post merchant_toggle_automation_path("welcome")
    assert_redirected_to merchant_automations_path
    assert autos.dig("welcome", "enabled")

    post merchant_toggle_automation_path("welcome")
    assert_not autos.dig("welcome", "enabled")
  end

  # `update` dựng lại cả cấu hình từ form, nên nếu nút bật đi qua đường đó thì
  # một cú bấm xoá sạch quà, số ngày và lời nhắn đã đặt.
  test "bật không làm mất phần đã cấu hình" do
    @ws.update!(settings: @ws.settings.merge(
      "automations" => { "winback" => { "enabled" => false, "reward_id" => @reward.id,
                                        "days" => 45, "message" => "Nhớ bạn lắm" } }))
    post merchant_toggle_automation_path("winback")
    cfg = autos["winback"]
    assert cfg["enabled"]
    assert_equal 45, cfg["days"]
    assert_equal "Nhớ bạn lắm", cfg["message"]
    assert_equal @reward.id, cfg["reward_id"]
  end

  # Chào mừng / Sinh nhật thiếu quà thì Automations thoát ngay, không tặng gì và
  # không báo gì — bật trong trạng thái đó là dựng một cái bẫy im lặng.
  test "chưa chọn quà thì không cho bật Chào mừng" do
    post merchant_toggle_automation_path("welcome")
    assert_redirected_to merchant_edit_automation_path("welcome")
    assert_not autos.dig("welcome", "enabled")
  end

  # Kéo khách quay lại vẫn gửi lời nhắc khi không có quà, nên nó được phép bật.
  test "Kéo khách quay lại bật được dù chưa có quà" do
    post merchant_toggle_automation_path("winback")
    assert autos.dig("winback", "enabled")
  end
end
