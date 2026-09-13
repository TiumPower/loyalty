require "test_helper"

# Reviews are shown publicly and drive the shop's average, so an accidental
# submission must not become a rating.
class ReviewRatingTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "reviewsmoke")
    ActsAsTenant.with_tenant(@ws) do
      WorkspaceBootstrap.call(@ws) if defined?(WorkspaceBootstrap)
      @member = create(:member, workspace: @ws, email: "r@example.com")
    end
    post "/w/#{@ws.slug}/login", params: { email: @member.email }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email, purpose: "login").order(:id).last
    post "/w/#{@ws.slug}/verify", params: { code: ch.code }
  end

  test "the form opens with no star chosen" do
    get "/w/#{@ws.slug}/review"
    assert_response :success
    assert_select "input[name=stars][value=?]", ""
  end

  test "submitting with no stars is rejected, not silently recorded" do
    assert_no_difference -> { Rating.unscoped.count } do
      post "/w/#{@ws.slug}/review", params: { stars: "", comment: "quên chấm sao" }
    end
    assert_response :unprocessable_entity
  end

  test "a blank star field is never treated as one star" do
    post "/w/#{@ws.slug}/review", params: { stars: "0", comment: "" }
    assert_equal 0, Rating.unscoped.count, "0 must not clamp up to a 1-star review"
  end

  test "a chosen rating is recorded as given" do
    assert_difference -> { Rating.unscoped.count }, 1 do
      post "/w/#{@ws.slug}/review", params: { stars: "3", comment: "ổn" }
    end
    assert_equal 3, Rating.unscoped.last.stars
  end
end
