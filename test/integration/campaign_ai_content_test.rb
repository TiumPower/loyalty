require "test_helper"
require "minitest/mock"

# The "✨ tạo bằng AI" button on the campaign form. The prompt must carry every
# field the merchant filled in section 1 — the campaign name included, since it
# is the merchant's own words for what the campaign is about.
class CampaignAiContentTest < ActionDispatch::IntegrationTest
  setup do
    # "trial" gives full feature access, so campaigns are not plan-gated here.
    @ws = create(:workspace, subdomain: "aigen", status: "trial")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
    end
    sign_in @user
  end

  # Capture the prompt handed to Claude without calling out to the network.
  def capture_prompt
    prompts = []
    fake = Object.new
    fake.define_singleton_method(:json) { |prompt, **| prompts << prompt; { "title" => "T", "body" => "B" } }
    ClaudeService.stub(:configured?, true) do
      ClaudeService.stub(:new, ->(*, **) { fake }) { yield }
    end
    prompts.last
  end

  test "the campaign name reaches the AI prompt" do
    prompt = capture_prompt do
      post "/merchant/campaigns/generate_content",
           params: { name: "Mừng khai trương chi nhánh Cầu Giấy",
                     campaign_type: "happy_hour", audience: "new" }
    end
    assert_response :success
    assert_includes prompt, "Mừng khai trương chi nhánh Cầu Giấy"
    assert_includes prompt, I18n.t("merchant.campaign_types.happy_hour")
    assert_includes prompt, I18n.t("merchant.campaign_audiences.new")
  end

  test "a blank name still generates" do
    prompt = capture_prompt do
      post "/merchant/campaigns/generate_content", params: { campaign_type: "promo_voucher", audience: "all" }
    end
    assert_response :success
    assert_not_includes prompt, "Tên chiến dịch"
  end

  # The AI banner used to be reachable only after the campaign existed.
  test "ticking the banner box on the create form queues the banner job" do
    AiImageService.stub(:configured?, true) do
      assert_enqueued_with(job: GenerateCampaignBannerJob) do
        post "/merchant/campaigns", params: {
          campaign: { name: "Giờ vàng thứ 5", campaign_type: "happy_hour", audience: "all", status: "running" },
          generate_banner: "1"
        }
      end
    end
    campaign = ActsAsTenant.with_tenant(@ws) { Campaign.order(:id).last }
    assert_redirected_to merchant_campaign_path(campaign)
    assert_equal "generating", campaign.banner_status
    assert campaign.banner_requested_at.present?
  end

  test "leaving the banner box unticked queues nothing" do
    AiImageService.stub(:configured?, true) do
      assert_no_enqueued_jobs(only: GenerateCampaignBannerJob) do
        post "/merchant/campaigns", params: {
          campaign: { name: "Không banner", campaign_type: "happy_hour", audience: "all", status: "running" }
        }
      end
    end
  end

  # A new campaign must not go live on its own: the merchant reviews it first,
  # and its claim QR must stay dead until then.
  test "a created campaign is not running and its promo QR is inactive" do
    reward = ActsAsTenant.with_tenant(@ws) do
      Reward.create!(workspace: @ws, title: "Cà phê", kind: "voucher", cost_points: 100,
                     value_unit: "item", active: true)
    end
    post "/merchant/campaigns", params: {
      campaign: { name: "Lì xì Tết", campaign_type: "promo_voucher", audience: "all", status: "draft",
                  reward_id: reward.id },
      generate_qr: "1", max_claims: "50"
    }
    campaign = ActsAsTenant.with_tenant(@ws) { Campaign.order(:id).last }
    assert_equal "draft", campaign.status
    assert_not campaign.live?
    promo = ActsAsTenant.with_tenant(@ws) { campaign.promo_codes.first }
    assert promo.present?
    assert_not promo.active?

    # Starting it flips both the campaign and its QR on.
    patch "/merchant/campaigns/#{campaign.id}/resume"
    assert_equal "running", campaign.reload.status
    assert promo.reload.active?
  end

  # A status the form cannot send must not sneak through either.
  test "the create form posts draft, not running" do
    get "/merchant/campaigns/new"
    assert_response :success
    assert_match(/value="draft"[^>]*name="campaign\[status\]"/, response.body)
    assert_no_match(/value="running"[^>]*name="campaign\[status\]"/, response.body)
  end

  # Baking the claim QR into the banner is the merchant's choice.
  test "the banner QR is only baked in when asked for and a QR exists" do
    reward = ActsAsTenant.with_tenant(@ws) do
      Reward.create!(workspace: @ws, title: "Trà sữa", kind: "voucher", cost_points: 80,
                     value_unit: "item", active: true)
    end
    last_id = -> { ActsAsTenant.with_tenant(@ws) { Campaign.order(:id).last.id } }

    AiImageService.stub(:configured?, true) do
      # Asked for, and the campaign does have a claim QR → baked in.
      post "/merchant/campaigns", params: {
        campaign: { name: "Có QR", campaign_type: "promo_voucher", audience: "all",
                    status: "draft", reward_id: reward.id },
        generate_qr: "1", generate_banner: "1", banner_include_qr: "1"
      }
      assert_equal [last_id.call, true], enqueued_jobs.last["arguments"]

      # Not asked for → plain banner.
      post "/merchant/campaigns", params: {
        campaign: { name: "Không QR", campaign_type: "promo_voucher", audience: "all",
                    status: "draft", reward_id: reward.id },
        generate_qr: "1", generate_banner: "1"
      }
      assert_equal [last_id.call, false], enqueued_jobs.last["arguments"]

      # Asked for, but no claim QR was created → nothing to bake in.
      post "/merchant/campaigns", params: {
        campaign: { name: "Không mã", campaign_type: "event", audience: "all", status: "draft" },
        generate_banner: "1", banner_include_qr: "1"
      }
      assert_equal [last_id.call, false], enqueued_jobs.last["arguments"]
    end
  end

  # The campaign page's banner button carries the same QR choice.
  test "the campaign page offers the banner QR choice and honours it" do
    reward = ActsAsTenant.with_tenant(@ws) do
      Reward.create!(workspace: @ws, title: "Bánh", kind: "voucher", cost_points: 50,
                     value_unit: "item", active: true)
    end
    campaign, promo = ActsAsTenant.with_tenant(@ws) do
      c = Campaign.create!(workspace: @ws, name: "Cuối tuần", campaign_type: "promo_voucher",
                           audience: "all", status: "running", reward: reward)
      [c, PromoCode.create!(workspace: @ws, campaign: c, reward: reward, active: true)]
    end
    assert promo.persisted?

    AiImageService.stub(:configured?, true) do
      get "/merchant/campaigns/#{campaign.id}"
      assert_response :success
      assert_match I18n.t("merchant.campaigns.banner_include_qr"), response.body

      patch "/merchant/campaigns/#{campaign.id}/generate_banner", params: { include_qr: "1" }
      assert_equal [campaign.id, true], enqueued_jobs.last["arguments"]
      assert_equal "generating", campaign.reload.banner_status

      patch "/merchant/campaigns/#{campaign.id}/generate_banner"
      assert_equal [campaign.id, false], enqueued_jobs.last["arguments"]
    end
  end
end
