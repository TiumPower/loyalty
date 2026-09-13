require "test_helper"

# Every screen a signed-in customer can reach in the PWA.
class CustomerPagesTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "custsmoke")
    ActsAsTenant.with_tenant(@ws) do
      WorkspaceBootstrap.call(@ws) if defined?(WorkspaceBootstrap)
      @member = create(:member, workspace: @ws, email: "cust@example.com")
    end
  end

  def base = "/w/#{@ws.slug}"

  # Go through the real OTP login rather than forging a session.
  def sign_in_member!
    post "#{base}/login", params: { email: @member.email }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email, purpose: "login")
                     .order(:id).last
    assert ch.present?, "no OTP challenge issued"
    post "#{base}/verify", params: { code: ch.code }
  end

  PAGES = %w[
    / /me /wallet /history /stamps /tier /badges
    /missions /refer /review /my-code /notifications /shop /wheel
  ].freeze

  PAGES.each do |suffix|
    test "customer page #{suffix} renders" do
      sign_in_member!
      get "#{base}#{suffix}"
      assert_includes [200, 302], response.status, "#{suffix} returned #{response.status}"
    end
  end

  test "a reward detail page renders" do
    reward = ActsAsTenant.with_tenant(@ws) { Reward.first }
    skip "no seeded reward" if reward.nil?
    sign_in_member!
    get "#{base}/rewards/#{reward.id}"
    assert_includes [200, 302], response.status
  end

  test "the login page renders for a signed-out visitor" do
    get "#{base}/login"
    assert_response :success
  end
end
