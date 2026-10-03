require "test_helper"

# Huy hiệu trước đây chỉ đến được qua trang Hạng, nên hầu như không khách nào
# biết quán có huy hiệu. Dải ở cuối màn hình chính tồn tại để trả lời đúng câu
# đó, nên nó phải cho thấy cả thứ ĐÃ có lẫn chỗ CÒN TRỐNG — một dải toàn huy
# hiệu đã đạt thì không dạy được gì.
class HomeBadgesTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "hbadge")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, gamification_enabled: true)
      @member = create(:member, workspace: @ws, email: "hb@example.com")
      @member.update!(lifetime_points: 500)
    end
  end

  def base = "/w/#{@ws.slug}"

  def sign_in!
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: { code: otp_code_for(@member.email, workspace: @ws) }
  end

  def badge(key, threshold)
    ActsAsTenant.with_tenant(@ws) do
      Badge.create!(workspace: @ws, key: key, name: "HH #{key}", criteria_type: "points_total",
                    threshold: threshold, position: Badge.count)
    end
  end

  test "dải huy hiệu hiện cả cái đã đạt lẫn cái còn trống" do
    badge("a", 100)   # 500/100 → đã đạt
    badge("b", 1000)  # 500/1000 → gần nhất
    badge("c", 9000)
    sign_in!
    get base
    assert_response :success

    assert_equal 3, css_select(".l-badges .chip").size
    assert_equal 2, css_select(".l-badges .chip.off").size, "hai cái chưa đạt phải trông như chỗ trống"
    assert_select ".l-badges .hd .tt", text: "1/3"
  end

  # Mốc đã đủ nhưng bản ghi chưa được ghi (quán vừa thêm huy hiệu mới, khách
  # chưa mở trang Huy hiệu) — màn hình chính cố ý KHÔNG chạy evaluate_badges vì
  # nó ghi bản ghi, cộng điểm và bắn thông báo. Nên ở đây phải tự coi là đã đạt,
  # nếu không khách thấy "500/100 chưa đạt".
  test "đủ mốc thì tính là đã đạt dù chưa có bản ghi" do
    badge("a", 100)
    sign_in!
    get base
    assert_equal 0, MemberBadge.unscoped.count, "trang chủ không được ghi gì"
    assert_empty css_select(".l-badges .chip.off")
  end

  # Đạt nhiều rồi vẫn phải thấy cái tiếp theo, nếu không mục này thành tủ kính.
  test "đạt nhiều rồi vẫn chừa chỗ cho cái chưa đạt" do
    6.times { |i| badge("done#{i}", 10) }
    3.times { |i| badge("next#{i}", 5_000 + i) }
    sign_in!
    get base
    assert_equal 6, css_select(".l-badges .chip").size, "dải giới hạn 6 đĩa"
    assert_equal 2, css_select(".l-badges .chip.off").size
  end

  # Chừa chỗ mà không có gì để xếp vào thì dải ngắn lại vô cớ.
  test "ít cái chưa đạt thì lấp nốt bằng cái đã đạt" do
    6.times { |i| badge("done#{i}", 10) }
    badge("next", 5_000)
    sign_in!
    get base
    assert_equal 6, css_select(".l-badges .chip").size
    assert_equal 1, css_select(".l-badges .chip.off").size
  end

  test "quán chưa mở huy hiệu nào thì không hiện gì" do
    sign_in!
    get base
    assert_response :success
    assert_empty css_select(".l-badges")
  end
end
