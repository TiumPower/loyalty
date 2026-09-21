require "test_helper"

# The public share page (/c/:slug) is what a Facebook/Zalo visitor lands on. It
# must always offer a way to claim: the banner's own QR, or a standalone one.
class PublicCampaignPageTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "sharepage", status: "trial")
    ActsAsTenant.with_tenant(@ws) do
      @reward = Reward.create!(workspace: @ws, title: "Cà phê", kind: "voucher",
                               cost_points: 100, value_unit: "item", active: true)
      @campaign = Campaign.create!(workspace: @ws, name: "Khai trương", campaign_type: "promo_voucher",
                                   audience: "all", status: "running", reward: @reward)
      @promo = PromoCode.create!(workspace: @ws, campaign: @campaign, reward: @reward, active: true)
    end
  end

  def attach_banner!(has_qr:)
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==")
    ActsAsTenant.with_tenant(@ws) do
      @campaign.banner.attach(io: StringIO.new(png), filename: "b.png", content_type: "image/png")
      @campaign.update!(banner_status: "ready", banner_has_qr: has_qr)
    end
  end

  test "a banner without a baked-in QR still gets a standalone QR" do
    attach_banner!(has_qr: false)
    get "/c/#{@campaign.share_token!}"
    assert_response :success
    assert_match "Quét mã để nhận ưu đãi", response.body
  end

  test "a banner that already carries the QR does not repeat it" do
    attach_banner!(has_qr: true)
    get "/c/#{@campaign.share_token!}"
    assert_response :success
    assert_no_match(/Quét mã để nhận ưu đãi/, response.body)
  end

  test "no banner at all falls back to the standalone QR" do
    get "/c/#{@campaign.share_token!}"
    assert_response :success
    assert_match "Quét mã để nhận ưu đãi", response.body
  end
end
