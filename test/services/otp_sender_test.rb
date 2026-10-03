require "test_helper"
require "minitest/mock"

# Which provider runs, and what happens when one of them fails. No network: the
# adapters are stubbed, because the thing under test is the dispatch decision.
class OtpSenderTest < ActiveSupport::TestCase
  ZNS  = { "ZALO_APP_ID" => "app", "ZALO_APP_SECRET" => "sec",
           "ZALO_ZNS_TEMPLATE_ID" => "tpl", "ZALO_OA_REFRESH_TOKEN" => "ref" }.freeze
  ESMS = { "ESMS_API_KEY" => "key", "ESMS_SECRET_KEY" => "sec",
           "ESMS_OA_ID" => "oa", "ESMS_TEMPLATE_ID" => "tpl" }.freeze

  # A stand-in adapter: returns whatever result the test wants, and counts calls
  # so "did we fall back?" is answerable.
  class FakeAdapter
    attr_reader :calls

    def initialize(result)
      @result = result
      @calls  = 0
    end

    def deliver(phone:, code:)
      @calls += 1
      @result
    end
  end

  def with_env(vars)
    previous = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def ok(provider)   = OtpSender::Result.new(ok: true, provider: provider, vendor_id: "x1")
  def bad(provider)  = OtpSender::Result.new(ok: false, provider: provider, error: "boom")

  def clear_env = (ZNS.keys + ESMS.keys + %w[OTP_ZALO_PROVIDER OTP_PROVIDER_FALLBACK]).index_with { nil }

  test "with no credentials nothing is configured and nothing is sent" do
    with_env(clear_env) do
      assert_not OtpSender.configured?
      result = OtpSender.deliver(phone: "0901234567", code: "123456")
      assert_not result.ok?
      assert_equal "not_configured", result.error
    end
  end

  test "auto-detect prefers our own Zalo OA over the reseller" do
    with_env(clear_env.merge(ZNS).merge(ESMS)) do
      assert OtpSender.configured?
      assert_equal "zns", OtpSender.primary
    end
  end

  test "auto-detect falls to the reseller when only it is configured" do
    with_env(clear_env.merge(ESMS)) do
      assert_equal "esms", OtpSender.primary
    end
  end

  test "an explicit provider wins over auto-detection" do
    with_env(clear_env.merge(ZNS).merge(ESMS).merge("OTP_ZALO_PROVIDER" => "esms")) do
      assert_equal "esms", OtpSender.primary
    end
  end

  # The kill switch has to work without touching credentials — that is the
  # point of it: turn delivery off during an incident, decide about keys later.
  test "provider 'none' is a hard off switch even with full credentials" do
    with_env(clear_env.merge(ZNS).merge(ESMS).merge("OTP_ZALO_PROVIDER" => "none")) do
      assert_not OtpSender.configured?
      assert_nil OtpSender.primary
      assert_not OtpSender.deliver(phone: "0901234567", code: "123456").ok?
    end
  end

  test "a failed primary falls back to the other provider when allowed" do
    primary  = FakeAdapter.new(bad("zns"))
    fallback = FakeAdapter.new(ok("esms"))
    with_env(clear_env.merge(ZNS).merge(ESMS).merge("OTP_PROVIDER_FALLBACK" => "true")) do
      ZaloZns.stub(:new, primary) do
        EsmsZns.stub(:new, fallback) do
          result = OtpSender.deliver(phone: "0901234567", code: "123456")
          assert result.ok?
          assert_equal "esms", result.provider
          assert_equal 1, primary.calls
          assert_equal 1, fallback.calls
        end
      end
    end
  end

  test "without the fallback flag a failure is not retried elsewhere" do
    primary  = FakeAdapter.new(bad("zns"))
    fallback = FakeAdapter.new(ok("esms"))
    with_env(clear_env.merge(ZNS).merge(ESMS).merge("OTP_PROVIDER_FALLBACK" => nil)) do
      ZaloZns.stub(:new, primary) do
        EsmsZns.stub(:new, fallback) do
          result = OtpSender.deliver(phone: "0901234567", code: "123456")
          assert_not result.ok?
          assert_equal 1, primary.calls
          assert_equal 0, fallback.calls
        end
      end
    end
  end

  test "a successful primary is not sent twice" do
    primary  = FakeAdapter.new(ok("zns"))
    fallback = FakeAdapter.new(ok("esms"))
    with_env(clear_env.merge(ZNS).merge(ESMS).merge("OTP_PROVIDER_FALLBACK" => "true")) do
      ZaloZns.stub(:new, primary) do
        EsmsZns.stub(:new, fallback) do
          assert OtpSender.deliver(phone: "0901234567", code: "123456").ok?
          assert_equal 1, primary.calls
          assert_equal 0, fallback.calls, "a delivered code must not be sent again — it costs money"
        end
      end
    end
  end

  test "missing_env names exactly what is still needed" do
    with_env(clear_env) do
      assert_includes ZaloZns.missing_env, "ZALO_APP_ID"
      assert_includes ZaloZns.missing_env, "ZALO_OA_REFRESH_TOKEN"
      assert_includes EsmsZns.missing_env, "ESMS_OA_ID"
    end
    with_env(clear_env.merge(ESMS)) { assert_empty EsmsZns.missing_env }
  end

  # The refresh token rotates, so after the first refresh the only current copy
  # lives in AppSetting — a stale ENV value must not make us look unconfigured.
  test "a stored refresh token substitutes for the env one" do
    with_env(clear_env.merge(ZNS).merge("ZALO_OA_REFRESH_TOKEN" => nil)) do
      assert_not ZaloZns.configured?
      AppSetting.set("zns_refresh_token", "rotated")
      assert ZaloZns.configured?
    ensure
      AppSetting.set("zns_refresh_token", "")
    end
  end
end
