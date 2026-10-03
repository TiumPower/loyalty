require "test_helper"

# Thẻ "Xem nhanh" của một khách có nút gửi thông báo, nằm ngay dưới tên và lịch
# sử mua hàng của người đó. Nó vốn mang theo bộ lọc của cả DANH SÁCH, nên bấm
# vào là soạn thông báo cho cả nhóm đang lọc — chủ quán tin mình đang nhắn cho
# một người.
class BroadcastSingleMemberTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace, subdomain: "one")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @target = create(:member, workspace: @ws, email: "target@example.com", name: "Đào Trịnh Vũ")
      @other  = create(:member, workspace: @ws, email: "other@example.com", name: "Người khác")
    end
    sign_in @user
  end

  test "gửi cho một khách thì chỉ người đó nhận" do
    post merchant_broadcasts_path, params: {
      when: "now",
      broadcast: { title: "Riêng bạn", body: "xin chào", segment_key: "all",
                   audience_member_id: @target.id }
    }
    assert_redirected_to merchant_broadcasts_path
    b = ActsAsTenant.with_tenant(@ws) { Broadcast.order(:id).last }
    assert_equal 1, b.sent_count
    assert_equal 1, @target.notifications.count
    assert_equal 0, @other.notifications.count
    assert_equal @target.display_name, b.audience_display, "nhãn phải là tên người nhận"
  end

  # Bộ lọc nhóm đi kèm phải bị bỏ qua: giao điểm của "một người" với "nhóm đang
  # lọc" có thể rỗng — gửi xong không ai nhận — hoặc tệ hơn, hoá ra cả nhóm.
  test "đã chỉ đích danh thì bộ lọc nhóm không còn tác dụng" do
    post merchant_broadcasts_path, params: {
      when: "now",
      broadcast: { title: "Riêng bạn", body: "x", segment_key: "vip",
                   audience_query: "Người khác", audience_member_id: @target.id }
    }
    b = ActsAsTenant.with_tenant(@ws) { Broadcast.order(:id).last }
    assert_equal 1, b.sent_count
    assert_equal 1, @target.notifications.count
    assert_equal 0, @other.notifications.count
  end

  # id là thứ người gửi tự gõ được; một shop không được soạn thông báo cho khách
  # của shop khác.
  test "không gửi được cho khách của workspace khác" do
    other_ws = create(:workspace, subdomain: "two")
    outsider = ActsAsTenant.with_tenant(other_ws) { create(:member, workspace: other_ws, email: "x@example.com") }
    get new_merchant_broadcast_path(member: outsider.id)
    assert_response :success
    assert_not_includes response.body, outsider.email
    post merchant_broadcasts_path, params: {
      when: "now",
      broadcast: { title: "Lạc", body: "x", segment_key: "all", audience_member_id: outsider.id }
    }
    assert_equal 0, outsider.notifications.count
  end

  test "lần gửi theo lịch cũng tìm lại đúng một người" do
    b = ActsAsTenant.with_tenant(@ws) do
      @ws.broadcasts.create!(title: "Hẹn giờ", body: "x", segment_key: "all",
                             created_by: @user, audience_member_id: @target.id)
    end
    ActsAsTenant.with_tenant(@ws) { b.deliver_to_segment! }
    assert_equal 1, @target.notifications.count
    assert_equal 0, @other.notifications.count
  end
end
