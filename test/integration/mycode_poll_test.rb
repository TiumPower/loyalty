require "test_helper"

# The "+X points" burst on the my-code screen. It used to key off a float
# timestamp: the time was sent to the phone as a float and rebuilt with
# Time.at, which drops part of a microsecond, so `created_at > since` stayed
# true for the very purchase just reported and the burst reopened itself every
# three seconds after the customer dismissed it.
class MyCodePollTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "poll")
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @outlet = @ws.outlets.first || Outlet.create!(workspace: @ws, name: "CN", active: true)
    end
    sign_in_member("poll@example.com")
    @member = ActsAsTenant.with_tenant(@ws) { Member.find_by(email: "poll@example.com") }
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member(email)
    post "#{base}/login", params: { email: email }
    post "#{base}/verify", params: { code: ActsAsTenant.with_tenant(@ws) { OtpChallenge.order(:created_at).last.code } }
  end

  def earn!(points = 50)
    ActsAsTenant.with_tenant(@ws) do
      Purchase.create!(workspace: @ws, member: @member, outlet: @outlet,
                       amount: points * 1000, points_earned: points, source: "staff_scan")
    end
  end

  test "an earn is reported once and never again" do
    purchase = earn!
    get "#{base}/my-code/recent", params: { after: 0 }, as: :json
    body = JSON.parse(response.body)
    assert_equal 50, body["earned"]
    assert_equal purchase.id, body["id"]

    # Asking again from the id just handed back must return nothing — this is
    # the loop that made the burst reappear.
    get "#{base}/my-code/recent", params: { after: body["id"] }, as: :json
    assert_nil JSON.parse(response.body)["earned"]
  end

  test "a later earn is still reported" do
    first = earn!(10)
    second = earn!(20)
    get "#{base}/my-code/recent", params: { after: first.id }, as: :json
    body = JSON.parse(response.body)
    assert_equal 20, body["earned"]
    assert_equal second.id, body["id"]
  end

  test "a voided bill is not announced" do
    p = earn!(30)
    ActsAsTenant.with_tenant(@ws) { p.update!(voided_at: Time.current) }
    get "#{base}/my-code/recent", params: { after: 0 }, as: :json
    assert_nil JSON.parse(response.body)["earned"]
  end
end
