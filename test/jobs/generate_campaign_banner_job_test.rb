require "test_helper"

# The banner is worth nothing without the scannable QR composited onto it, and
# a campaign created from the form starts out not-running with a dormant QR.
class GenerateCampaignBannerJobTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "bannerjob", status: "trial")
    ActsAsTenant.with_tenant(@ws) do
      @reward = Reward.create!(workspace: @ws, title: "Cà phê", kind: "voucher",
                               cost_points: 100, value_unit: "item", active: true)
      @campaign = Campaign.create!(workspace: @ws, name: "Khai trương", campaign_type: "promo_voucher",
                                   audience: "all", status: "draft", reward: @reward)
      @promo = PromoCode.create!(workspace: @ws, campaign: @campaign, reward: @reward, active: false)
    end
  end

  def scan_url(campaign)
    GenerateCampaignBannerJob.new.send(:promo_scan_url, campaign)
  end

  test "a not-yet-started campaign still gets its dormant QR composited" do
    assert_includes scan_url(@campaign).to_s, @promo.token
  end

  test "a paused campaign's disabled QR is not put on a banner" do
    @campaign.update!(status: "paused")
    assert_nil scan_url(@campaign)
  end

  test "a running campaign uses its active QR" do
    @campaign.update!(status: "running")
    @promo.update!(active: true)
    assert_includes scan_url(@campaign).to_s, @promo.token
  end
end
