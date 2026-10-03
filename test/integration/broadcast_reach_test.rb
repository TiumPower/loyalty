require "test_helper"

# Danh sách thông báo từng chỉ hiện MỘT con số — `sent_count`, kèm chữ "khách".
# Con số đó là thư vào hộp thư trong ứng dụng, không phải số điện thoại đã reo.
# Chủ quán đọc "10 khách" rồi không hiểu vì sao máy mình im: không một ai trong
# nhóm đó cài app. Hai con số khác nhau thì phải hiện cả hai.
class BroadcastReachTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace, subdomain: "reach")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @with_app = create(:member, workspace: @ws, email: "app@example.com")
      @without  = create(:member, workspace: @ws, email: "noapp@example.com")
      PushSubscription.create!(workspace: @ws, member: @with_app,
                               endpoint: "https://web.push.apple.com/x", p256dh: "p", auth: "a")
    end
    sign_in @user
  end

  def send_to(members)
    ActsAsTenant.with_tenant(@ws) do
      b = @ws.broadcasts.create!(title: "Khuyến mãi", body: "test", segment_key: "all", created_by: @user)
      b.deliver!(members)
      b.reload
    end
  end

  test "ghi lại bao nhiêu máy thật sự nhận được đẩy" do
    ENV["VAPID_PUBLIC_KEY"] = ENV["VAPID_PRIVATE_KEY"] = "x"
    b = send_to([@with_app, @without])
    assert_equal 2, b.sent_count, "cả hai đều có thư trong app"
    assert_equal 1, b.push_count, "chỉ một người cài app"
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end

  # Đúng cái đã xảy ra thật: gửi cho một nhóm mà không ai cài app.
  test "nhóm không ai cài app thì nói thẳng là không máy nào nhận" do
    ENV["VAPID_PUBLIC_KEY"] = ENV["VAPID_PRIVATE_KEY"] = "x"
    send_to([@without])
    get merchant_broadcasts_path
    assert_response :success
    assert_select ".bc-push.none"
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end

  # Bản gửi cũ không có số này; 0 là một lời nói dối khác ("đẩy tới 0 người")
  # so với "không biết".
  test "bản gửi cũ không bịa ra con số" do
    ActsAsTenant.with_tenant(@ws) do
      @ws.broadcasts.create!(title: "Cũ", body: "x", segment_key: "all",
                             created_by: @user, sent_count: 5, sent_at: 1.day.ago)
    end
    get merchant_broadcasts_path
    assert_response :success
    assert_empty css_select(".bc-push")
  end

  # Thiết kế thẻ đã nằm sẵn trong file từ đầu nhưng markup vẫn là <table> ép
  # rộng 800px — trên màn hẹp phải kéo ngang mới đọc được trạng thái.
  test "danh sách là thẻ, không phải bảng kéo ngang" do
    send_to([@without])
    get merchant_broadcasts_path
    assert_select ".bc-card"
    assert_empty css_select("table.m-table")
  end
end
