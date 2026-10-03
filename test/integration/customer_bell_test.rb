require "test_helper"

# Chấm đỏ trên chuông chỉ nói "có gì đó mới". Con số nói CÓ BAO NHIÊU — tức là
# có đáng mở ngay không. Kiểu `.l-iconbtn .num` đã nằm sẵn trong CSS từ lâu mà
# chưa chỗ nào dùng.
class CustomerBellTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "bell")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @member = create(:member, workspace: @ws, email: "bell@example.com")
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: { code: otp_code_for(@member.email, workspace: @ws) }
  end

  def base = "/w/#{@ws.slug}"

  def notify!(n)
    ActsAsTenant.with_tenant(@ws) do
      n.times { |i| Notification.create!(workspace: @ws, member: @member, title: "Tin #{i}", body: "x", kind: "promo") }
    end
  end

  test "chưa có gì chưa đọc thì chuông để trơn" do
    get base
    assert_response :success
    assert_empty css_select(".l-iconbtn .num")
  end

  test "hiện đúng số chưa đọc" do
    notify!(3)
    get base
    assert_select ".l-iconbtn .num", text: "3"
  end

  # Ô chuông chỉ rộng chừng đó, mà sau con số thứ hai thì "nhiều" đã đủ.
  test "quá chín thì rút thành 9+" do
    notify!(12)
    get base
    assert_select ".l-iconbtn .num", text: "9+"
  end
end
