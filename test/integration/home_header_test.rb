require "test_helper"

# Số điểm là con số khách mở app ra để xem. Nó từng nằm trong một tấm thẻ cao
# phía dưới thẻ quán — phải cuộn mới thấy. Giờ nó đứng ngay cạnh tên.
class HomeHeaderTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "hdr", name: "Mộc Cà Phê")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, points_expiry_months: 6)
      @member = create(:member, workspace: @ws, email: "hdr@example.com", name: "Lê Quốc Viên")
      PointTransaction.create!(workspace: @ws, member: @member, kind: "earn", amount: 1250)
      @member.recompute_points!
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email).order(:id).last.code
    }
  end

  def base = "/w/#{@ws.slug}"

  test "tên và điểm nằm cùng một hàng, không phải hai khối rời" do
    get base
    assert_response :success
    assert_select "header.l-head .l-ptspill", 1
    assert_select "header.l-head .t", /Viên/
    assert_match "1.250", css_select("header.l-head .l-ptspill").first.text.gsub(",", ".")
  end

  test "viên điểm dẫn tới lịch sử điểm" do
    get base
    assert_select "header.l-head a.l-ptspill[href=?]", "#{base}/history"
  end

  # Tấm thẻ số dư cũ phải biến mất hẳn, nếu không số điểm hiện hai lần.
  test "không còn tấm thẻ số dư trùng lặp" do
    get base
    assert_select ".l-screen .l-balance", 0
  end

  # Điểm sắp hết hạn là thứ duy nhất trên màn hình này có hạn chót, nên nó
  # chiếm dòng phụ ngay dưới tên thay vì một khối riêng.
  test "điểm sắp hết hạn chiếm dòng phụ dưới tên" do
    ActsAsTenant.with_tenant(@ws) do
      PointTransaction.where(member: @member).update_all(expires_at: 10.days.from_now)
    end
    get base
    assert_select "header.l-head .s.expiring", 1
  end

  test "không có gì sắp hết hạn thì dòng phụ là lời chào của quán" do
    get base
    assert_select "header.l-head .s.expiring", 0
    assert_select "header.l-head .s", /#{Regexp.escape(@ws.name)}/
  end
end
