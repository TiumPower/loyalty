require "test_helper"

# Hàng "Chơi & tích" và hàng "Nhiệm vụ" nằm sát nhau trên trang chủ, nên chúng
# phải trông như một bộ. Trước đây thẻ nhiệm vụ dùng đĩa tròn đặc còn thẻ vòng
# quay / thẻ tem dùng ô bo góc nền nhạt — hai thiết kế cạnh nhau.
class HomeCardsTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "cards")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, gamification_enabled: true, stamps_enabled: true)
      reward = create(:reward, workspace: @ws, cost_points: 300)
      StampCard.create!(workspace: @ws, title: "Mua 9 tặng 1", target_count: 9,
                        reward: reward, active: true, icon: "🧋")
      @ws.missions.create!(title: "Check-in", mission_type: "checkin", period: "daily",
                           goal: 1, reward_points: 20, position: 0, active: true)
      @member = create(:member, workspace: @ws, email: "cards@example.com")
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: otp_code_for(@member.email, workspace: @ws)
    }
  end

  def base = "/w/#{@ws.slug}"

  test "mọi thẻ nhỏ trên trang chủ dùng cùng một kiểu biểu tượng" do
    get base
    assert_response :success
    icons = css_select(".l-mini .ic")
    assert icons.size >= 2, "phải có ít nhất thẻ tem và thẻ nhiệm vụ"
    # Emoji của quán không được lọt vào đĩa đặc màu thương hiệu — trên nền đó
    # emoji nhiều màu đọc không ra; design dùng glyph trắng.
    icons.each do |ic|
      assert ic.css("svg").any? || ic.text.strip.match?(/\A[0-9✓]+\z/),
             "biểu tượng phải là glyph hoặc con số, gặp: #{ic.text.strip.inspect}"
    end
  end

  # Design để các dòng meta nhỏ là chữ trần; bọc pill làm thẻ hẹp trông như
  # một hàng nút bấm.
  test "dòng trạng thái là chữ, không phải viên pill" do
    get base
    assert_select ".l-mini .note", { minimum: 1 }
    assert_select ".l-mini .ft .l-pill", 1, "chỉ còn đúng viên điểm thưởng"
  end

  test "thẻ tem vẫn giữ emoji của quán ở trang Thẻ tem" do
    get "#{base}/stamps"
    assert_match "🧋", response.body
  end
end
