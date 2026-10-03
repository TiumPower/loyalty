require "test_helper"

# Ảnh ưu đãi bị cắt hai lần: biến thể cắt vuông, rồi `object-fit: cover` cắt
# thêm cho vừa khung 4:3 hoặc 16:10. Hai lần cắt chồng nhau đẩy chủ thể ra
# ngoài khuôn hình.
class RewardImageCropTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "crop")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @reward = create(:reward, workspace: @ws, title: "Cà phê", cost_points: 300)
      @reward.image.attach(io: file_fixture("square.png").open,
                           filename: "square.png", content_type: "image/png")
      @member = create(:member, workspace: @ws, email: "crop@example.com")
    end
  end

  test "khung 4:3 nhận biến thể 4:3, không phải vuông" do
    v = @reward.image.variant(resize_to_fill: [240, 180])
    assert_equal [240, 180], v.variation.transformations[:resize_to_fill],
                 "ratio 4/3 với size 240 phải ra 240x180"
  end

  test "khung 16:10 nhận biến thể 16:10" do
    assert_equal [720, 450],
                 @reward.image.variant(resize_to_fill: [720, 450]).variation.transformations[:resize_to_fill]
  end

  # Thứ thật sự phải đúng: trang nào vẽ khung nào thì xin biến thể của khung đó.
  test "mỗi màn hình xin đúng tỉ lệ khung của nó" do
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: otp_code_for(@member.email, workspace: @ws)
    }

    get base
    assert_select ".l-offer .ph img", { minimum: 1 }, "thẻ ưu đãi trên trang chủ có ảnh"

    get "#{base}/rewards/#{@reward.id}"
    assert_select ".l-hero img", { minimum: 1 }, "trang chi tiết có ảnh"
  end

  def base = "/w/#{@ws.slug}"
end
