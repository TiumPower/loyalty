require "test_helper"

# Which shop the merchant dashboard manages, and whether the address bar says
# so. The host is only a preference: a merchant who opens another shop's
# subdomain was quietly served their OWN shop under that shop's address.
class MerchantHostTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @mine   = create(:workspace, subdomain: "highland")
    @theirs = create(:workspace, subdomain: "cozycafe")
    # Otherwise every request bounces to the onboarding wizard and hides the
    # redirect under test.
    [@mine, @theirs].each { |w| w.update!(settings: w.settings.merge("onboarded" => true)) }
    @user = create(:user)
    ActsAsTenant.with_tenant(@mine) { Membership.create!(user: @user, workspace: @mine, role: "owner") }
    sign_in @user
  end

  # canonical_merchant_host only runs in production, where shops live on
  # subdomains at all.
  def as_production(&blk)
    across_hosts do
      was = Rails.env
      Rails.env = "production"
      begin
        blk.call
      ensure
        Rails.env = was
      end
    end
  end

  # The point of the bug report: the URL said cozycafe and the page said
  # Highland.
  test "another shop's subdomain sends the merchant to their own" do
    as_production do
      host! "cozycafe.#{ApplicationController::PLATFORM_HOST}"
      get "/merchant"
    end
    assert_response :redirect
    assert_equal "https://highland.#{ApplicationController::PLATFORM_HOST}/merchant",
                 response.location
  end

  test "a deep link keeps its path across the bounce" do
    as_production do
      host! "cozycafe.#{ApplicationController::PLATFORM_HOST}"
      get "/merchant/scanner"
    end
    assert_equal "https://highland.#{ApplicationController::PLATFORM_HOST}/merchant/scanner",
                 response.location
  end

  test "their own subdomain is left alone" do
    as_production do
      host! "highland.#{ApplicationController::PLATFORM_HOST}"
      get "/merchant"
    end
    assert_response :success
  end

  # The bare platform host is how people log in and pick a shop. Bouncing it
  # would be a redirect in everybody's way.
  test "the platform host itself is not a shop and stays put" do
    as_production do
      host! ApplicationController::PLATFORM_HOST
      get "/merchant"
    end
    assert_response :success
  end

  # The gate that matters: whatever the host says, queries are scoped to the
  # workspace the user actually belongs to.
  test "no host ever grants access to a shop the user is not in" do
    host! "cozycafe.#{ApplicationController::PLATFORM_HOST}"
    get "/merchant"
    assert_response :success
    assert_match @mine.name, response.body, "the dashboard names the shop it manages"
    refute_match @theirs.name, response.body, "and never the one it does not"
  end
end
