require "test_helper"
require "minitest/mock"

# The two decisions this model now owns: which channel a code goes out on, and
# whether it may be printed on the screen instead.
class OtpChallengeTest < ActiveSupport::TestCase
  SCOPE = "customer".freeze
  FLAG  = AppSetting::SHOW_OTP_KEY

  ZNS = { "ZALO_APP_ID" => "app", "ZALO_APP_SECRET" => "sec",
          "ZALO_ZNS_TEMPLATE_ID" => "tpl", "ZALO_OA_REFRESH_TOKEN" => "ref" }.freeze

  setup do
    @ws = create(:workspace)
    AppSetting.set_flag(FLAG, false)
    AppSetting.set("zns_verified_at", "")
  end

  teardown do
    AppSetting.set_flag(FLAG, false)
    AppSetting.set("zns_verified_at", "")
  end

  def with_env(vars)
    previous = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def in_production(&blk) = Rails.stub(:env, ActiveSupport::StringInquirer.new("production"), &blk)

  def issue(identifier, **opts)
    with_tenant(@ws) do
      OtpChallenge.issue!(identifier: identifier, scope: SCOPE, workspace: @ws, **opts)
    end
  end

  # ---- identifier normalisation -------------------------------------------

  test "the identifier is canonicalised by shape, not by scope" do
    assert_equal "me@example.com", OtpChallenge.normalize("  Me@Example.COM ")
    assert_equal "0901234567",     OtpChallenge.normalize("+84 901 234 567")
  end

  test "a challenge is found again however the number was typed the second time" do
    issue("0901234567")
    found = with_tenant(@ws) do
      OtpChallenge.latest_for(identifier: "+84901234567", scope: SCOPE, workspace: @ws)
    end
    assert found.present?, "the same number in another spelling must find the same challenge"
  end

  # A login code must not satisfy a different flow, and vice versa.
  test "purpose is part of the lookup" do
    issue("me@example.com", purpose: "login")
    with_tenant(@ws) do
      assert_nil OtpChallenge.latest_for(identifier: "me@example.com", scope: SCOPE,
                                         workspace: @ws, purpose: "email_change")
    end
  end

  # ---- channel choice -----------------------------------------------------

  test "an email identifier always goes by email" do
    with_env(ZNS) do
      AppSetting.set("zns_verified_at", Time.current.to_i.to_s)
      assert_equal "email", OtpChallenge.pick_channel(identifier: "me@example.com", workspace: @ws)
    end
  end

  # Until a live Zalo send has actually worked, a configured-but-unproven
  # provider must not take a working email channel away from people.
  test "a phone prefers a known-good email channel until Zalo has proven itself" do
    member = with_tenant(@ws) { create(:member, workspace: @ws, phone: "0901234567", email: "has@example.com") }
    assert member.persisted?
    with_env(ZNS) do
      EmailOtp.stub(:configured?, true) do
        assert_equal "email", OtpChallenge.pick_channel(identifier: "0901234567", workspace: @ws)

        AppSetting.set("zns_verified_at", Time.current.to_i.to_s)
        assert_equal "zalo", OtpChallenge.pick_channel(identifier: "0901234567", workspace: @ws)
      end
    end
  end

  test "a phone with no profile email goes to Zalo" do
    with_env(ZNS) do
      EmailOtp.stub(:configured?, true) do
        assert_equal "zalo", OtpChallenge.pick_channel(identifier: "0909999999", workspace: @ws)
      end
    end
  end

  # ---- showing the code on screen -----------------------------------------

  test "outside production the code is always on screen" do
    assert issue("0901234567").show_on_screen?
  end

  test "in production with nothing configured the code is on screen" do
    # Otherwise the login screen would be a dead end: no channel, no code.
    challenge = issue("0901234567")
    in_production { assert challenge.show_on_screen? }
  end

  test "in production a configured Zalo gateway keeps the code off the screen" do
    challenge = issue("0901234567")
    with_env(ZNS) { in_production { assert_not challenge.show_on_screen? } }
  end

  test "the operator switch puts the code back on screen" do
    challenge = issue("0901234567")
    with_env(ZNS) do
      in_production do
        AppSetting.set_flag(FLAG, true)
        assert challenge.show_on_screen?
      end
    end
  end

  # The security property of the whole feature: a provider outage must not turn
  # into "here is everyone's login code" for every account on the platform.
  test "a failed delivery NEVER reveals the code" do
    challenge = issue("0901234567")
    challenge.update_columns(delivery_error: "500 vendor down")
    with_env(ZNS) { in_production { assert_not challenge.show_on_screen? } }
  end

  # ---- verification -------------------------------------------------------

  test "verify reports each outcome distinctly" do
    challenge = issue("0901234567")
    assert_equal :mismatch, challenge.verify("000000")
    assert_equal :ok, challenge.verify(challenge.code)
    assert_equal :expired, challenge.verify(challenge.code), "a consumed code cannot be reused"

    again = issue("0901234567")
    OtpChallenge::MAX_ATTEMPTS.times { again.verify("000000") }
    assert_equal :too_many, again.verify(again.code)

    stale = issue("0901234567")
    stale.update_columns(expires_at: 1.minute.ago)
    assert_equal :expired, stale.verify(stale.code)
  end
end
