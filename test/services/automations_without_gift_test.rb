require "test_helper"

# Quà là TUỲ CHỌN. Trước đây Chào mừng và Sinh nhật thiếu quà là cả tự động hoá
# im lặng không chạy — bật lên rồi ngồi đợi, không ai nhận gì và không có dòng
# log nào nói vì sao. Nhưng một lời chào mừng không quà vẫn là một lời chào
# mừng, và quán chưa kịp dựng ưu đãi thì đó là tất cả những gì họ cần.
class AutomationsWithoutGiftTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "autogift")
    ActsAsTenant.with_tenant(@ws) { create(:loyalty_program, workspace: @ws) }
  end

  def configure(kind, **cfg)
    @ws.update!(settings: @ws.settings.merge("automations" => { kind => { "enabled" => true }.merge(cfg.stringify_keys) }))
  end

  def member!(**attrs)
    ActsAsTenant.with_tenant(@ws) { create(:member, workspace: @ws, **attrs) }
  end

  test "chào mừng không quà vẫn gửi lời chào" do
    configure("welcome")
    m = member!(email: "a@example.com")
    ActsAsTenant.with_tenant(@ws) { Automations.on_signup(m) }
    assert_equal 1, m.notifications.count
    assert_equal 0, m.vouchers.count, "không hứa quà thì không tạo voucher"
  end

  test "chào mừng có quà thì vẫn tặng như cũ" do
    reward = ActsAsTenant.with_tenant(@ws) { create(:reward, workspace: @ws) }
    configure("welcome", reward_id: reward.id)
    m = member!(email: "b@example.com")
    ActsAsTenant.with_tenant(@ws) { Automations.on_signup(m) }
    assert_equal 1, m.vouchers.count
    assert_match reward.title, m.notifications.first.body
  end

  # Quán đã chọn quà nhưng ưu đãi đó bị xoá: im lặng còn hơn gửi một lời chào
  # hụt mất món quà đã hứa.
  test "quà đã chọn mà không còn thì không gửi gì" do
    reward = ActsAsTenant.with_tenant(@ws) { create(:reward, workspace: @ws) }
    configure("welcome", reward_id: reward.id)
    ActsAsTenant.with_tenant(@ws) { reward.destroy }
    m = member!(email: "c@example.com")
    ActsAsTenant.with_tenant(@ws) { Automations.on_signup(m) }
    assert_equal 0, m.notifications.count
  end

  test "sinh nhật không quà vẫn gửi lời chúc, và chỉ một lần mỗi năm" do
    configure("birthday")
    m = member!(email: "d@example.com", birthday: Date.new(1990, Date.current.month, Date.current.day))
    assert_equal 1, Automations.run_birthday
    assert_equal 1, m.notifications.count
    assert_equal 0, Automations.run_birthday, "chạy lại trong ngày không gửi thêm"
    assert_equal 1, m.reload.notifications.count
  end
end
