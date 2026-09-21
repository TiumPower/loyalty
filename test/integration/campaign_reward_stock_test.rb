require "test_helper"

# A campaign built on a sold-out reward sends customers to a QR that always
# refuses, so the merchant must not be able to build one.
class CampaignRewardStockTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "stockguard", status: "trial")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @plenty = Reward.create!(workspace: @ws, title: "Còn suất", kind: "gift",
                               value_unit: "item", active: true, stock: 5, redeemed_count: 1)
      @sold_out = Reward.create!(workspace: @ws, title: "Hết suất", kind: "gift",
                                 value_unit: "item", active: true, stock: 2, redeemed_count: 2)
    end
    sign_in @user
  end

  test "a sold-out reward is not offered when creating a campaign" do
    get "/merchant/campaigns/new"
    assert_response :success
    assert_match "Còn suất", response.body
    assert_no_match(/value="#{@sold_out.id}"/, response.body)
  end

  test "posting a sold-out reward is refused, not silently accepted" do
    assert_no_difference -> { ActsAsTenant.with_tenant(@ws) { Campaign.count } } do
      post "/merchant/campaigns", params: {
        campaign: { name: "Tặng quà", campaign_type: "promo_voucher", audience: "all",
                    status: "draft", reward_id: @sold_out.id },
        generate_qr: "1"
      }
    end
    assert_response :unprocessable_entity
    assert_match I18n.t("merchant.rewards.reward_unavailable", title: "Hết suất",
                        reason: I18n.t("merchant.rewards.unassignable.out_of_stock")), response.body
  end

  test "an unlimited reward (no stock set) is always offered" do
    unlimited = ActsAsTenant.with_tenant(@ws) do
      Reward.create!(workspace: @ws, title: "Không giới hạn", kind: "gift",
                     value_unit: "item", active: true, stock: nil, redeemed_count: 99)
    end
    get "/merchant/campaigns/new"
    assert_match(/value="#{unlimited.id}"/, response.body)
  end

  # A campaign whose prize runs out later must stay editable — dropping the
  # reward from the picker would silently detach it on the next save.
  test "a campaign keeps its own reward after it sells out" do
    campaign = ActsAsTenant.with_tenant(@ws) do
      c = Campaign.create!(workspace: @ws, name: "Đang chạy", campaign_type: "promo_voucher",
                           audience: "all", status: "running", reward: @plenty)
      @plenty.update!(redeemed_count: @plenty.stock) # sells out afterwards
      c
    end
    get "/merchant/campaigns/#{campaign.id}/edit"
    assert_response :success
    assert_match(/value="#{@plenty.id}"/, response.body)
    assert_match I18n.t("merchant.campaigns.reward_opt_sold_out").strip, response.body

    patch "/merchant/campaigns/#{campaign.id}", params: {
      campaign: { name: "Đổi tên", campaign_type: "promo_voucher", audience: "all",
                  status: "running", reward_id: @plenty.id }
    }
    assert_redirected_to merchant_campaign_path(campaign)
    assert_equal @plenty.id, campaign.reload.reward_id
    assert_equal "Đổi tên", campaign.name
  end

  test "swapping to a sold-out reward on an existing campaign is refused" do
    campaign = ActsAsTenant.with_tenant(@ws) do
      Campaign.create!(workspace: @ws, name: "Đang chạy", campaign_type: "promo_voucher",
                       audience: "all", status: "running", reward: @plenty)
    end
    patch "/merchant/campaigns/#{campaign.id}", params: {
      campaign: { name: "Đang chạy", campaign_type: "promo_voucher", audience: "all",
                  status: "running", reward_id: @sold_out.id }
    }
    assert_response :unprocessable_entity
    assert_equal @plenty.id, campaign.reload.reward_id
  end
end
