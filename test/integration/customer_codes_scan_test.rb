require "test_helper"

# "Mã của tôi" and the customer scanner. Both screens live on a phone held at a
# counter, and both talk to the customer through JavaScript.
class CustomerCodesScanTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "codesws")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000)
      @member = create(:member, workspace: @ws, email: "code@example.com")
    end
    sign_in_member!
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member!
    post "#{base}/login", params: { email: @member.email }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email, purpose: "login").order(:id).last
    post "#{base}/verify", params: { code: ch.code }
  end

  # The countdown was seeded with a literal 45 while the token actually lives
  # for MemberQr::TTL, so the first paint told the customer the wrong number and
  # then jumped.
  test "the countdown starts at the real token lifetime" do
    get "#{base}/my-code"
    assert_response :success
    assert_select "[data-mycode-target=count]", text: MemberQr::TTL.to_s
    assert_select "[data-mycode-ttl-value=?]", MemberQr::TTL.to_s
  end

  # Every message the scanner shows while asking for the camera was written into
  # the JavaScript in Vietnamese, so an English customer was told in Vietnamese
  # that their camera was blocked.
  test "the scanner's camera messages follow the customer's language" do
    get "#{base}/scan?locale=en"
    assert_response :success
    %w[scanning denied unsupported failed].each do |k|
      assert_select "[data-qrnav-#{k}-text-value]"
    end
    body = response.body
    refute_match "Đang quét", body
    refute_match "Camera đang bị chặn", body
    assert_match "Scanning", body

    get "#{base}/scan"
    assert_response :success
    assert_match "Đang quét", response.body
  end

  test "the earn burst formats numbers for the customer's locale" do
    get "#{base}/my-code?locale=en"
    assert_response :success
    assert_select "[data-mycode-locale-value=?]", "en"
    get "#{base}/my-code"
    assert_select "[data-mycode-locale-value=?]", "vi"
  end

  # The personal QR is short-lived on purpose: a screenshot taken at the counter
  # must not work at another till later.
  test "a member QR stops working once it has expired" do
    ActsAsTenant.with_tenant(@ws) do
      token = MemberQr.encode(@member)
      assert_equal @member.id, MemberQr.decode(token, workspace: @ws)&.id

      travel (MemberQr::TTL + 5).seconds do
        assert_nil MemberQr.decode(token, workspace: @ws), "an expired code is refused"
        assert_nil ScanRouter.member(token, @ws)
      end
    end
  end

  # A token minted by one shop must never resolve at another.
  test "a member QR from another shop is refused" do
    other = create(:workspace, subdomain: "otherws")
    token = ActsAsTenant.with_tenant(@ws) { MemberQr.encode(@member) }
    assert_nil ActsAsTenant.with_tenant(other) { MemberQr.decode(token, workspace: other) }
  end
end
