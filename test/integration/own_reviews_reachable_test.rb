require "test_helper"

# The redesign folded the old "your reviews" tab into one list. The list shows
# three by default, so a member whose review has scrolled out of it needs
# another way back to edit it.
class OwnReviewsReachableTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "ownrev")
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @ws.update!(settings: @ws.settings.merge("feedback_public" => true))
    end
    sign_in_member("me@example.com")
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member(email)
    post "#{base}/login", params: { email: email }
    code = ActsAsTenant.with_tenant(@ws) { OtpChallenge.order(:created_at).last.code }
    post "#{base}/verify", params: { code: code }
  end

  test "my own review stays reachable once newer ones push it down the list" do
    post "#{base}/review", params: { stars: 4, comment: "Của tôi" }
    mine = ActsAsTenant.with_tenant(@ws) { Rating.order(:id).last }

    # Four newer reviews from other people bury it past the three shown.
    ActsAsTenant.with_tenant(@ws) do
      4.times do |i|
        Rating.create!(workspace: @ws, member: create(:member, workspace: @ws),
                       stars: 5, comment: "Khách khác #{i}", created_at: (i + 1).minutes.from_now)
      end
    end

    get "#{base}/shop"
    assert_response :success
    assert_match "/review/#{mine.id}", response.body,
                 "the member needs a link back to their own review"
  end
end
