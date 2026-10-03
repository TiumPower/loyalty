require "test_helper"

# Ưu đãi chưa có ảnh. Trước đây chỗ đó là một emoji lửng lơ giữa ô trống —
# nằm cạnh những thẻ có ảnh thật thì đọc như ảnh hỏng.
class RewardArtTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "art")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @reward = create(:reward, workspace: @ws, title: "Cà phê miễn phí", cost_points: 300)
      @member = create(:member, workspace: @ws, email: "art@example.com")
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: otp_code_for(@member.email, workspace: @ws)
    }
  end

  def base = "/w/#{@ws.slug}"

  test "ưu đãi không ảnh vẫn lấp đầy khung bằng nền thương hiệu" do
    get base
    assert_response :success
    assert_select ".l-offer .ph .l-artfallback", { minimum: 1 },
                  "phải có nền thay ảnh, không để ô trống"
    assert_select ".l-artfallback .em", { minimum: 1 }, "biểu tượng vẫn nằm trong đó"
  end

  test "ưu đãi có ảnh thì dùng ảnh, không chèn nền thay thế" do
    ActsAsTenant.with_tenant(@ws) do
      @reward.image.attach(io: file_fixture("square.png").open,
                           filename: "square.png", content_type: "image/png")
    end
    get base
    assert_select ".l-offer .ph img", { minimum: 1 }
    assert_select ".l-offer .ph .l-artfallback", 0
  end

  test "trang chi tiết ưu đãi cũng dùng cùng một nền" do
    get "#{base}/rewards/#{@reward.id}"
    assert_response :success
    assert_select ".l-hero .l-artfallback", { minimum: 1 }
  end
end
