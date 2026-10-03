require "test_helper"

# Huy hiệu hạng được cắt mặt như đá quý: nhiều mặt phẳng cùng màu, khác
# `fill-opacity`. Trước đây mỗi hạng là một hình đặc một khối lấy từ bộ icon
# giao diện — đúng hình nhưng phẳng lì, và trang hạng còn vẽ nét ở cỡ 46px
# trong khi mọi nơi khác tô đặc.
class TierBadgeTest < ActionDispatch::IntegrationTest
  include IconsHelper

  setup do
    @ws = create(:workspace, subdomain: "gem", name: "Mộc Cà Phê")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, tiers_enabled: true)
      [["bronze", "Đồng", 0, 0], ["silver", "Bạc", 1, 2000],
       ["gold", "Vàng", 2, 5000], ["diamond", "Kim Cương", 3, 10_000]].each do |key, name, pos, th|
        @ws.tiers.find_or_create_by!(key: key) do |t|
          t.name = name; t.position = pos; t.threshold_points = th; t.multiplier = 1
        end
      end
      @member = create(:member, workspace: @ws, email: "gem@example.com", name: "Lê Quốc Viên")
      PointTransaction.create!(workspace: @ws, member: @member, kind: "earn", amount: 6_000)
      @member.recompute_points!
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: otp_code_for(@member.email, workspace: @ws)
    }
  end

  def base = "/w/#{@ws.slug}"

  test "mỗi hạng là một viên đá nhiều mặt, không phải một khối đặc" do
    IconsHelper::TIER_BADGES.each do |key, body|
      facets = body.scan(/fill-opacity="([0-9.]+)"/).flatten.map(&:to_f)
      assert facets.size >= 3, "#{key}: #{facets.size} mặt — quá ít để ra khối"
      assert facets.uniq.size >= 2, "#{key}: mọi mặt cùng độ đậm, vẫn là hình phẳng"
      assert_operator facets.min, :>=, 0.5, "#{key}: mặt nhạt nhất mờ quá, cỡ 13px sẽ mất chữ"
      assert_equal 1.0, facets.max, "#{key}: không mặt nào đậm hết, huy hiệu nhẹ hơn chữ cạnh nó"
    end
  end

  # Huy hiệu nằm trên nền kem, nền gradient và nền trắng; màu do hạng tự mang
  # trong DB. Một mã màu cứng lọt vào là hỏng ở một trong ba chỗ.
  test "huy hiệu chỉ dùng currentColor, không màu cứng" do
    IconsHelper::TIER_BADGES.each do |key, body|
      assert_no_match(/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/, body, "#{key}: có màu cứng")
      assert_no_match(/\bfill="(?!none)/, body, "#{key}: mặt tự đặt fill, không theo currentColor")
    end
  end

  test "nước cắt dày dần theo hạng" do
    counts = IconsHelper::TIER_BADGES.transform_values { |b| b.scan("<path").size }
    assert_operator counts[:bronze], :<, counts[:gold], "Đồng phải là viên cắt đơn giản nhất"
    assert_operator counts[:bronze], :<, counts[:diamond]
  end

  test "trang hạng vẽ huy hiệu đặc, không còn vẽ nét ở cỡ lớn" do
    get "#{base}/tier"
    assert_response :success
    assert_select "svg[fill=currentColor] path[fill-opacity]", minimum: 3
    assert_select "svg[stroke=currentColor][width=46]", 0, "cỡ 46px từng vẽ nét, lệch với mọi nơi khác"
  end

  test "huy hiệu theo đúng hạng hiện tại ở trang chủ" do
    get base
    assert_response :success
    gold = IconsHelper::TIER_BADGES[:gold].scan(/d="([^"]+)"/).flatten.first
    assert_includes response.body, gold, "6.000 điểm là hạng Vàng, huy hiệu phải là viên Vàng"
  end

  # Workspace tự đặt tên hạng ("Thân thiết", "VIP"…) thì không khớp khoá nào;
  # lúc đó bậc thang theo `position` mới là thứ quyết định.
  test "hạng tên lạ rơi về nấc thang theo thứ tự" do
    ActsAsTenant.with_tenant(@ws) do
      vip = @ws.tiers.new(key: "vip", name: "VIP", position: 2, threshold_points: 9_999, multiplier: 1)
      assert_equal :gold, ApplicationController.helpers.tier_icon(vip)
      assert_equal :bronze, ApplicationController.helpers.tier_icon(nil)
    end
  end
end
