require "test_helper"

# Phone + OTP is now the default way into the customer app, with email kept for
# accounts that predate it. Both paths go through one action, so both are
# covered here.
class CustomerPhoneLoginTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "phonelogin")
    ActsAsTenant.with_tenant(@ws) { WorkspaceBootstrap.call(@ws) if defined?(WorkspaceBootstrap) }
  end

  def base = "/w/#{@ws.slug}"

  def login_with_phone(phone)
    post "#{base}/login", params: { tab: "phone", phone: phone }
    code = otp_code_for(phone, workspace: @ws)
    assert code.present?, "no OTP challenge was issued for #{phone}"
    post "#{base}/verify", params: { code: code }
    code
  end

  test "the login screen defaults to the phone tab and offers email as the other" do
    get "#{base}/login"
    assert_response :success
    assert_select "input[name=?]", "phone"
    assert_select "a[href=?]", "#{base}/login?tab=email"
  end

  test "a first-time visitor signing in by phone gets a membership" do
    assert_difference -> { ActsAsTenant.with_tenant(@ws) { Member.count } }, 1 do
      login_with_phone("0901234567")
    end
    assert_redirected_to base

    member = ActsAsTenant.with_tenant(@ws) { Member.find_by(phone: "0901234567") }
    assert_equal "direct", member.join_source
    get "#{base}/"
    assert_response :success
  end

  # The whole point of canonicalising: one person must not end up with two
  # memberships because they typed their own number differently.
  test "a second sign-in in another spelling reuses the same membership" do
    login_with_phone("0901234567")
    delete "#{base}/logout"

    assert_no_difference -> { ActsAsTenant.with_tenant(@ws) { Member.count } } do
      login_with_phone("+84 901 234 567")
    end
  end

  # A walk-in whose profile the shop already created must land in THAT profile,
  # with their points, not a fresh empty one.
  test "an existing member is signed in to their own profile" do
    member = ActsAsTenant.with_tenant(@ws) { create(:member, workspace: @ws, phone: "0907654321") }

    assert_no_difference -> { ActsAsTenant.with_tenant(@ws) { Member.count } } do
      login_with_phone("0907654321")
    end
    assert_equal member.id, ActsAsTenant.with_tenant(@ws) { Member.find_by(phone: "0907654321").id }
  end

  test "a wrong code is rejected and signs nobody in" do
    post "#{base}/login", params: { tab: "phone", phone: "0901234567" }
    post "#{base}/verify", params: { code: "000000" }
    assert_response :unprocessable_entity

    get "#{base}/"
    assert_redirected_to "#{base}/login"
  end

  test "a malformed number is refused before any code is issued" do
    assert_no_difference -> { OtpChallenge.unscoped.count } do
      post "#{base}/login", params: { tab: "phone", phone: "12" }
    end
    assert_response :unprocessable_entity
  end

  # REGRESSION LOCK: two dozen tests (and any customer mid-login across a
  # deploy) post an email with no `tab` param. The controller infers the tab
  # from the params for exactly this reason — do not "tidy" that away.
  test "an email login with no tab param still works" do
    post "#{base}/login", params: { email: "old@example.com" }
    code = otp_code_for("old@example.com", workspace: @ws)
    assert code.present?, "no OTP challenge was issued for the email"
    post "#{base}/verify", params: { code: code }
    assert_redirected_to base

    get "#{base}/"
    assert_response :success
  end

  test "the email tab issues an email-channel code" do
    post "#{base}/login", params: { tab: "email", email: "Me+tag@Gmail.com" }
    # Canonicalised on the way in, so alias tricks cannot farm separate accounts.
    challenge = otp_challenge_for("me@gmail.com", workspace: @ws)
    assert challenge.present?
    assert_equal "email", challenge.channel
  end

  test "a phone code records the Zalo channel" do
    post "#{base}/login", params: { tab: "phone", phone: "0901234567" }
    assert_equal "zalo", otp_challenge_for("0901234567", workspace: @ws).channel
  end
end
