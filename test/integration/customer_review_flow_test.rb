require "test_helper"

class CustomerReviewFlowTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "reviewshop", name: "Gấu Coffee")
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @apology_reward = create(:reward, workspace: @ws, title: "Free upsize", cost_points: nil)
      @ws.update!(settings: @ws.settings.merge(
        "google_review_url" => "https://g.page/r/abc/review",
        "automations" => { "low_rating" => { "enabled" => true,
                                             "reward_id" => @apology_reward.id.to_s,
                                             "threshold" => 3 } }
      ))
    end
    sign_in_member("fan@example.com")
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member(email)
    post "#{base}/login", params: { email: email }
    code = ActsAsTenant.with_tenant(@ws) { OtpChallenge.order(:created_at).last.code }
    post "#{base}/verify", params: { code: code }
  end

  # The POST must redirect, not render: Turbo silently discards a 200 response to
  # a form submission, which left the customer looking at the untouched form.
  test "a happy review lands on the thank-you page with the public review CTA" do
    post "#{base}/review", params: { stars: 5, comment: "Cà phê ngon" }
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_match I18n.t("customer.review_thanks.google_cta"), response.body
    assert_match "https://g.page/r/abc/review", response.body
  end

  test "a low review triggers the apology reward and alerts the merchant" do
    assert_difference -> { ActsAsTenant.with_tenant(@ws) { Voucher.count } }, 1 do
      post "#{base}/review", params: { stars: 2, comment: "Đợi lâu" }
    end
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_match I18n.t("customer.review_thanks.apology_title"), response.body
    # No public-review nudge for an unhappy customer.
    assert_no_match(/g\.page/, response.body)

    alert = ActsAsTenant.with_tenant(@ws) { MerchantAlert.where(kind: "rating").last }
    assert_not_nil alert
    assert_equal "danger", alert.level
  end

  test "the apology reward is not farmable by repeat low reviews" do
    assert_difference -> { ActsAsTenant.with_tenant(@ws) { Voucher.count } }, 1 do
      post "#{base}/review", params: { stars: 1 }
      post "#{base}/review", params: { stars: 1 }
      post "#{base}/review", params: { stars: 1 }
    end
  end

  test "the shop page shows the merchant's reply" do
    post "#{base}/review", params: { stars: 4, comment: "Ổn" }
    ActsAsTenant.with_tenant(@ws) do
      Rating.last.update!(reply_body: "Cảm ơn bạn nhiều!", replied_at: Time.current)
    end
    get "#{base}/shop"
    assert_response :success
    assert_match "Cảm ơn bạn nhiều!", response.body
    assert_match I18n.t("customer.review_reply.from_shop", shop: @ws.name), response.body
  end
end
