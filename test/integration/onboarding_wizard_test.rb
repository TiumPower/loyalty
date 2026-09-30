require "test_helper"

# Every step of the setup wizard renders (the two-column steps were restructured).
class OnboardingWizardTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "onb")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: @user, workspace: @ws, role: "owner") }
    sign_in @user
  end

  (1..4).each do |n|
    test "step #{n} renders" do
      get "/merchant/onboarding?step=#{n}"
      assert_response :success
    end
  end
end
