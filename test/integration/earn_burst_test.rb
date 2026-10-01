require "test_helper"

# The "+X điểm" reveal on "Mã của tôi" — the screen a customer is actually
# watching while the cashier rings the bill up. It used to be a slab of scanner
# black with a bare number on it; it now draws the same receipt the full earn
# screen does, from the same poll.
class EarnBurstTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "burst")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000)
      @outlet = @ws.outlets.first || Outlet.create!(workspace: @ws, name: "Thảo Điền", active: true)
      @member = create(:member, workspace: @ws, email: "burst@example.com")
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email).order(:id).last.code
    }
  end

  def base = "/w/#{@ws.slug}"

  def earn!(amount)
    ActsAsTenant.with_tenant(@ws) do
      EarnPoints.new(member: @member, amount: amount, outlet: @outlet, source: "staff_scan").call
    end
  end

  test "the poll carries enough to draw a receipt, not just a number" do
    before = ActsAsTenant.with_tenant(@ws) { @member.purchases.maximum(:id).to_i }
    result = earn!(120_000)

    get "#{base}/my-code/recent", params: { after: before }, as: :json
    assert_response :success
    body = JSON.parse(response.body)

    assert_equal result.points, body["earned"]
    assert_equal "#{@ws.name} · #{@outlet.name}", body["place"],
                 "the branch is what makes it checkable"
    assert_equal "120.000", body["amount"], "the bill, grouped for reading"
    assert body["at"].present?
    assert_equal @member.reload.points_balance, body["balance"]
  end

  # Points that did not come from a bill — a check-in, a mission, an
  # adjustment — are ledger entries, not purchases. The reveal is about the
  # counter ringing something up, so those must not pop it.
  test "points that are not a purchase do not pop the reveal" do
    before = ActsAsTenant.with_tenant(@ws) { @member.purchases.maximum(:id).to_i }
    ActsAsTenant.with_tenant(@ws) do
      PointTransaction.create!(workspace: @ws, member: @member, kind: "mission", amount: 20)
      @member.recompute_points!
    end
    get "#{base}/my-code/recent", params: { after: before }, as: :json
    assert_nil JSON.parse(response.body)["earned"]
  end

  # Plenty of one-branch shops name the branch after the shop. Joining the two
  # unconditionally produced "Highland · Highland" on a customer's phone.
  test "a branch named after its shop is not said twice" do
    ActsAsTenant.with_tenant(@ws) { @outlet.update!(name: @ws.name) }
    before = ActsAsTenant.with_tenant(@ws) { @member.purchases.maximum(:id).to_i }
    earn!(50_000)
    get "#{base}/my-code/recent", params: { after: before }, as: :json
    assert_equal @ws.name, JSON.parse(response.body)["place"]
  end

  # "Highland Lê Lợi" already carries the shop name; prefixing it again gives
  # "Highland · Highland Lê Lợi".
  test "a branch that already carries the shop name stands alone" do
    ActsAsTenant.with_tenant(@ws) { @outlet.update!(name: "#{@ws.name} Lê Lợi") }
    before = ActsAsTenant.with_tenant(@ws) { @member.purchases.maximum(:id).to_i }
    earn!(50_000)
    get "#{base}/my-code/recent", params: { after: before }, as: :json
    assert_equal "#{@ws.name} Lê Lợi", JSON.parse(response.body)["place"]
  end

  test "nothing new means nothing to show" do
    after = ActsAsTenant.with_tenant(@ws) { @member.purchases.maximum(:id).to_i }
    get "#{base}/my-code/recent", params: { after: after }, as: :json
    assert_nil JSON.parse(response.body)["earned"]
  end

  # The reveal is a celebration now, and it sits in light chrome that scrolls —
  # the dark overlay had its button pinned off the bottom of a short phone.
  test "the reveal is a congratulation in the app's own chrome" do
    get "#{base}/my-code"
    assert_response :success
    assert_select ".l-burst .l-result .halo.solid", 1
    assert_select ".l-burst [data-mycode-target=burstBalance]", 1
    assert_select ".l-burst [data-mycode-target=burstAmount]", 1
    assert_match I18n.t("customer.my_code.verified"), response.body
  end
end
