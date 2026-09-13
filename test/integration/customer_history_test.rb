require "test_helper"

# The points ledger as the customer sees it. It is the only place they can check
# the shop's arithmetic, so it has to be complete, stable and cheap.
class CustomerHistoryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace, subdomain: "histws")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000)
      @outlet = @ws.outlets.create!(name: "Chi nhánh 1", active: true)
      @member = create(:member, workspace: @ws, email: "hist@example.com")
    end
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member!
    post "#{base}/login", params: { email: @member.email }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email, purpose: "login").order(:id).last
    post "#{base}/verify", params: { code: ch.code }
  end

  def tx(n, at: Time.current, kind: "earn", **rest)
    ActsAsTenant.with_tenant(@ws) do
      @member.point_transactions.create!(
        { workspace: @ws, kind: kind, amount: n, outlet: @outlet, created_at: at }.merge(rest)
      )
    end
  end

  # Every row rendered its outlet name off its own association, so a full page
  # cost one query per row on top of the page itself.
  test "the page does not run a query per row" do
    30.times { |i| tx(10, at: i.minutes.ago) }
    sign_in_member!

    outlet_queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      outlet_queries += 1 if payload[:sql].to_s.include?('FROM "outlets"')
    end
    get "#{base}/history"
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_response :success
    assert outlet_queries <= 2, "expected the outlets to be preloaded, got #{outlet_queries} queries"
  end

  # A purchase writes several rows in the same instant. Ordered on created_at
  # alone, Postgres is free to return ties in any order, so paging could show
  # the same row twice and never show another.
  test "paging is stable when rows share a timestamp" do
    same = 3.hours.ago
    40.times { tx(5, at: same) }
    sign_in_member!

    get "#{base}/history"
    assert_response :success
    first_page = response.body.scan(/data-tx-id="(\d+)"/).flatten
    get "#{base}/history?page=2"
    second_page = response.body.scan(/data-tx-id="(\d+)"/).flatten

    assert_equal 30, first_page.size
    assert_equal 10, second_page.size
    assert_empty first_page & second_page, "a row appeared on both pages"
    assert_equal 40, (first_page | second_page).size, "a row was never shown"
  end

  # An "earn" row said "Tích điểm từ hoá đơn" with no bill on it, so the one
  # question this screen exists to answer — why did I get this many points —
  # could not be checked against anything.
  test "an earn row shows the bill it came from" do
    ActsAsTenant.with_tenant(@ws) do
      EarnPoints.new(member: @member, amount: 250_000, outlet: @outlet, source: "staff_scan").call
    end
    sign_in_member!
    get "#{base}/history"
    assert_response :success
    assert_match "250.000", response.body
  end

  # The adjustment reason is free text typed by the shop and printed verbatim on
  # this screen, so it is bounded at the point it is written.
  test "a merchant adjustment reason reaches the customer intact but bounded" do
    tx(-50, kind: "adjust", note: "Trừ nhầm hôm qua", outlet: nil)
    sign_in_member!
    get "#{base}/history"
    assert_response :success
    assert_match "Trừ nhầm hôm qua", response.body

    owner = create(:user)
    member = @member
    ActsAsTenant.with_tenant(@ws) do
      @ws.memberships.create!(user: owner, role: "owner")
      member.point_transactions.create!(workspace: @ws, kind: "earn", amount: 5_000)
      member.recompute_points!
    end
    sign_in owner
    post adjust_merchant_customer_path(member),
         params: { amount: -10, note: "x" * (Merchant::CustomersController::MAX_NOTE + 1) }
    assert_redirected_to merchant_customer_path(member)
    assert_match(/quá dài/, flash[:alert].to_s)
  end
end
