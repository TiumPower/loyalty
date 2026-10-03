require "test_helper"
require "minitest/mock"

# The two Zalo adapters, against a stubbed HTTP connection. What matters here is
# the wire format (these are paid, external APIs we cannot try in a test) and
# that a bad phone number never reaches them.
class ZaloProvidersTest < ActiveSupport::TestCase
  ZNS  = { "ZALO_APP_ID" => "app", "ZALO_APP_SECRET" => "sec",
           "ZALO_ZNS_TEMPLATE_ID" => "tpl-1", "ZALO_OA_REFRESH_TOKEN" => "ref" }.freeze
  ESMS = { "ESMS_API_KEY" => "key", "ESMS_SECRET_KEY" => "sec",
           "ESMS_OA_ID" => "oa-9", "ESMS_TEMPLATE_ID" => "tpl-2" }.freeze

  def with_env(vars)
    previous = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # A Faraday connection that records what was posted and replays a canned body.
  def stub_connection(body, status: 200, sink: {})
    Faraday.new do |f|
      f.adapter :test do |stub|
        stub.post(/.*/) do |env|
          sink[:url]     = env.url.to_s
          sink[:body]    = (JSON.parse(env.body) rescue env.body)
          sink[:headers] = env.request_headers
          [status, { "Content-Type" => "application/json" }, body]
        end
      end
    end
  end

  # ---- eSMS ---------------------------------------------------------------

  test "eSMS posts the documented ZNS payload and reads CodeResult 100 as sent" do
    sink = {}
    conn = stub_connection('{"CodeResult":"100","SMSID":"abc123"}', sink: sink)
    with_env(ESMS) do
      OtpSender.stub(:connection, conn) do
        result = EsmsZns.new.deliver(phone: "0901234567", code: "654321")
        assert result.ok?
        assert_equal "esms", result.provider
        assert_equal "abc123", result.vendor_id
      end
    end

    assert_equal EsmsZns::SEND_URL, sink[:url]
    assert_equal "key",   sink[:body]["ApiKey"]
    assert_equal "oa-9",  sink[:body]["OAID"]
    assert_equal "tpl-2", sink[:body]["TempID"]
    # The vendor wants the country-code form, never the local 0-prefixed one.
    assert_equal "84901234567", sink[:body]["Phone"]
    assert_equal({ "otp" => "654321" }, sink[:body]["TempData"])
    # RequestId is what stops a Faraday retry being charged (and delivered) twice.
    assert sink[:body]["RequestId"].present?
    assert_equal "0", sink[:body]["Sandbox"]
  end

  test "eSMS reports the vendor's own error code rather than a bare false" do
    conn = stub_connection('{"CodeResult":"101","ErrorMessage":"Authorize Failed"}')
    with_env(ESMS) do
      OtpSender.stub(:connection, conn) do
        result = EsmsZns.new.deliver(phone: "0901234567", code: "654321")
        assert_not result.ok?
        assert_match(/101/, result.error)
        assert_match(/Authorize Failed/, result.error)
      end
    end
  end

  test "eSMS honours the sandbox flag" do
    sink = {}
    conn = stub_connection('{"CodeResult":"100"}', sink: sink)
    with_env(ESMS.merge("ESMS_SANDBOX" => "true")) do
      OtpSender.stub(:connection, conn) { EsmsZns.new.deliver(phone: "0901234567", code: "1") }
    end
    assert_equal "1", sink[:body]["Sandbox"]
  end

  # ---- Zalo OA (ZNS) ------------------------------------------------------

  test "ZNS posts the template payload with the access token in the header" do
    sink = {}
    conn = stub_connection('{"error":0,"message":"Success","data":{"msg_id":"m-7"}}', sink: sink)
    with_env(ZNS) do
      AppSetting.set("zns_access_token", "live-token")
      AppSetting.set("zns_token_expiry", (Time.now.to_i + 3600).to_s)
      OtpSender.stub(:connection, conn) do
        result = ZaloZns.new.deliver(phone: "+84 901 234 567", code: "111222")
        assert result.ok?, result.error
        assert_equal "zns", result.provider
        assert_equal "m-7", result.vendor_id
      end
    ensure
      AppSetting.set("zns_access_token", "")
      AppSetting.set("zns_token_expiry", "0")
    end

    assert_equal ZaloZns::SEND_URL, sink[:url]
    assert_equal "live-token", sink[:headers]["access_token"]
    assert_equal "tpl-1", sink[:body]["template_id"]
    # "+84 901 234 567" and "0901234567" are the same person.
    assert_equal "84901234567", sink[:body]["phone"]
    assert_equal({ "otp" => "111222" }, sink[:body]["template_data"])
  end

  test "ZNS treats a non-zero error field as a failure" do
    conn = stub_connection('{"error":-124,"message":"Access token is invalid"}')
    with_env(ZNS) do
      AppSetting.set("zns_access_token", "live-token")
      AppSetting.set("zns_token_expiry", (Time.now.to_i + 3600).to_s)
      OtpSender.stub(:connection, conn) do
        result = ZaloZns.new.deliver(phone: "0901234567", code: "1")
        assert_not result.ok?
        assert_match(/-124/, result.error)
      end
    ensure
      AppSetting.set("zns_access_token", "")
      AppSetting.set("zns_token_expiry", "0")
    end
  end

  # The superseded token is kept because Zalo revokes it on rotation: if a
  # rotation is ever clobbered, this is the difference between a manual fix and
  # re-authorizing the Official Account from scratch.
  test "a token refresh stores the new pair and keeps the previous refresh token" do
    conn = stub_connection('{"access_token":"new-at","refresh_token":"new-rt","expires_in":"3600"}')
    with_env(ZNS) do
      AppSetting.set("zns_access_token", "")
      AppSetting.set("zns_token_expiry", "0")
      AppSetting.set("zns_refresh_token", "old-rt")
      OtpSender.stub(:connection, conn) do
        assert_equal "new-at", ZaloZns.new.send(:refresh!)
      end
      assert_equal "new-at", AppSetting.get("zns_access_token")
      assert_equal "new-rt", AppSetting.get("zns_refresh_token")
      assert_equal "old-rt", AppSetting.get("zns_refresh_token_prev")
    ensure
      %w[zns_access_token zns_refresh_token zns_refresh_token_prev].each { |k| AppSetting.set(k, "") }
      AppSetting.set("zns_token_expiry", "0")
    end
  end

  # ---- Shared guard -------------------------------------------------------

  # Garbage must not reach a paid API, and it must not be reported as sent.
  test "neither adapter calls out for an unusable phone number" do
    conn = stub_connection('{"CodeResult":"100"}')
    called = false
    tracking = Faraday.new { |f| f.adapter(:test) { |s| s.post(/.*/) { called = true; [200, {}, "{}"] } } }

    with_env(ZNS.merge(ESMS)) do
      OtpSender.stub(:connection, tracking) do
        ["", "abc", "12", nil].each do |junk|
          assert_equal "bad_phone", EsmsZns.new.deliver(phone: junk, code: "1").error
          assert_equal "bad_phone", ZaloZns.new.deliver(phone: junk, code: "1").error
        end
      end
    end
    assert_not called, "an unusable number must be rejected before any request"
    assert conn # silence unused warning
  end

  test "PhoneFormat masks a number down to something safe to log" do
    assert_equal "0901***567", PhoneFormat.mask("0901234567")
    assert_equal "***", PhoneFormat.mask("123")
    assert_equal "***", PhoneFormat.mask(nil)
  end
end
