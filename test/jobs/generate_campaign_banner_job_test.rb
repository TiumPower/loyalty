require "test_helper"
require "minitest/mock"

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

  # A 1x1 PNG is enough: the composer is stubbed out in these tests.
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==")

  # Runs the job with the image API and the compositor stubbed; returns the
  # qr_url the compositor was handed (nil = banner without a QR).
  def run_job(with_qr)
    seen = []
    image = Object.new
    image.define_singleton_method(:generate) { |_prompt| { bytes: PNG, content_type: "image/png" } }
    composer = ->(ai_bytes:, qr_url:) do
      seen << qr_url
      Object.new.tap { |o| o.define_singleton_method(:call) { ai_bytes } }
    end
    AiImageService.stub(:configured?, true) do
      AiImageService.stub(:new, ->(*, **) { image }) do
        BannerComposer.stub(:new, composer) do
          GenerateCampaignBannerJob.perform_now(@campaign.id, with_qr)
        end
      end
    end
    seen.last
  end

  test "with_qr bakes the promo QR in and records it on the campaign" do
    assert_includes run_job(true).to_s, @promo.token
    @campaign.reload
    assert_equal "ready", @campaign.banner_status
    assert @campaign.banner_has_qr?
    assert @campaign.banner.attached?
  end

  # Asked for a plain banner → no QR anywhere on it, and the public share page
  # must know so it can show its own QR instead.
  test "without with_qr the banner carries no QR" do
    assert_nil run_job(false)
    assert_not @campaign.reload.banner_has_qr?
  end
end
