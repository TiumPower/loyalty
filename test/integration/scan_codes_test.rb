require "test_helper"

# Scanning happens on a phone at a counter, so the second tap on a slow network
# is the normal case, not an edge case. Every code path a QR lands on has to
# survive being hit twice at once.
class ScanCodesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace)
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000)
      @outlet = @ws.outlets.create!(name: "Chi nhánh 1", active: true)
      @member = create(:member, workspace: @ws)
      @mission = @ws.missions.create!(title: "Check-in hôm nay", mission_type: "checkin",
                                      goal: 1, reward_points: 20, active: true)
    end
  end

  # Two taps on the check-in QR both passed the "already checked in today" test
  # before either wrote, so both went on to create the same MissionProgress row.
  # The unique index caught it, which meant the customer got an error page.
  test "a second check-in in the same breath is refused, not crashed on" do
    ActsAsTenant.with_tenant(@ws) do
      # The racing request loaded the member before the first scan landed, so its
      # copy still says "not checked in today".
      stale = Member.find(@member.id)
      assert_nil stale.last_checkin_at

      assert_equal [:done, 20], Checkin.check_in!(@member, @ws, @outlet)

      status, points = Checkin.check_in!(stale, @ws, @outlet)
      assert_equal :already, status
      assert_equal 0, points
      assert_equal 20, @member.reload.point_transactions.where(kind: "mission").sum(:amount),
                   "one check-in, one award"
      assert_equal 1, MissionProgress.where(member_id: @member.id, mission_id: @mission.id).count
    end
  end

  test "check-in is idempotent under real concurrency" do
    statuses = []
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActsAsTenant.with_tenant(@ws) do
            statuses << Checkin.check_in!(Member.find(@member.id), @ws, @outlet)
          end
        rescue => e
          statuses << e.class.name
        end
      end
    end
    threads.each(&:join)

    ActsAsTenant.with_tenant(@ws) do
      assert_equal 1, statuses.count { |s| s.is_a?(Array) && s.first == :done }, statuses.inspect
      refute statuses.any? { |s| s.is_a?(String) }, "no request may blow up: #{statuses.inspect}"
      assert_equal 20, @member.reload.point_transactions.where(kind: "mission").sum(:amount)
    end
  end

  # The one-claim-per-member check sat outside the lock, so a double-scanned
  # promo QR ran it twice and the unique index turned the second request into a
  # 500 instead of "bạn đã nhận rồi".
  test "a promo QR scanned twice reports already claimed" do
    ActsAsTenant.with_tenant(@ws) do
      reward = create(:reward, workspace: @ws, cost_points: nil, valid_days: 30)
      promo  = @ws.promo_codes.create!(reward: reward, active: true, max_claims: 10)

      v1, e1 = promo.claim!(@member)
      assert_nil e1
      assert v1

      # Same member again, from a copy that hasn't seen the first claim.
      v2, e2 = PromoCode.find(promo.id).claim!(Member.find(@member.id))
      assert_equal :already, e2
      assert_equal v1.id, v2.id
      assert_equal 1, PromoClaim.where(promo_code_id: promo.id).count
      assert_equal 1, Voucher.where(member_id: @member.id, source: "claim_qr").count
      assert_equal 1, promo.reload.claims_count
    end
  end

  test "a promo QR survives two simultaneous scans by one member" do
    reward = ActsAsTenant.with_tenant(@ws) { create(:reward, workspace: @ws, cost_points: nil, valid_days: 30) }
    promo  = ActsAsTenant.with_tenant(@ws) { @ws.promo_codes.create!(reward: reward, active: true, max_claims: 10) }

    results = []
    2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActsAsTenant.with_tenant(@ws) { results << PromoCode.find(promo.id).claim!(Member.find(@member.id)).last }
        rescue => e
          results << e.class.name
        end
      end
    end.each(&:join)

    ActsAsTenant.with_tenant(@ws) do
      refute results.any? { |r| r.is_a?(String) }, "no request may blow up: #{results.inspect}"
      assert_equal 1, PromoClaim.where(promo_code_id: promo.id).count
      assert_equal 1, Voucher.where(member_id: @member.id, source: "claim_qr").count
      assert_equal 1, promo.reload.claims_count
      assert_equal 1, reward.reload.redeemed_count, "stock is claimed once"
    end
  end

  # The rotate action, the model method and its notice all existed; nothing in
  # the app linked to any of them, so a merchant whose poster had been
  # photographed had no remedy at all.
  test "a manager can reach the rotate control from the branch QR screen" do
    owner = create(:user)
    cashier = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      @ws.memberships.create!(user: owner, role: "owner")
      @ws.memberships.create!(user: cashier, role: "staff", outlet: @outlet)
    end

    sign_in owner
    get merchant_scanner_checkin_qr_path
    assert_response :success
    assert_select "form[action=?]", merchant_rotate_checkin_path
    before = @ws.reload.checkin_nonce

    post merchant_rotate_checkin_path, headers: { "HTTP_REFERER" => merchant_scanner_checkin_qr_path }
    assert_redirected_to merchant_scanner_checkin_qr_path
    refute_equal before, @ws.reload.checkin_nonce
    sign_out owner

    # A cashier neither sees the button nor may use it.
    sign_in cashier
    get merchant_scanner_checkin_qr_path
    assert_select "form[action=?]", merchant_rotate_checkin_path, count: 0
    nonce = @ws.reload.checkin_nonce
    post merchant_rotate_checkin_path
    assert_redirected_to merchant_root_path
    assert_equal nonce, @ws.reload.checkin_nonce
  end

  # The redirect follows the referer, so it must never follow one off-site.
  test "rotate only ever returns to one of our own screens" do
    owner = create(:user)
    ActsAsTenant.with_tenant(@ws) { @ws.memberships.create!(user: owner, role: "owner") }
    sign_in owner
    post merchant_rotate_checkin_path, headers: { "HTTP_REFERER" => "https://evil.example/steal" }
    assert_redirected_to merchant_root_path
  end

  # End to end: the exact URL the merchant screen puts in the QR, scanned by a
  # signed-in customer, has to award the check-in — and a poster from before a
  # rotate has to stop working.
  test "the printed QR url resolves for a customer, and stops after a rotate" do
    ActsAsTenant.with_tenant(@ws) { @member.update!(email: "scan@example.com") }
    base = "/w/#{@ws.slug}"
    post "#{base}/login", params: { email: "scan@example.com" }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: "scan@example.com", purpose: "login").order(:id).last
    post "#{base}/verify", params: { code: ch.code }

    url = ActsAsTenant.with_tenant(@ws) do
      Rails.application.routes.url_helpers.member_scan_resolve_path(
        workspace_slug: @ws.slug, checkin: Checkin.encode(@ws, @outlet)
      )
    end

    get url
    assert_response :success
    assert_equal 20, @member.reload.point_transactions.where(kind: "mission").sum(:amount)

    # Same poster, second scan: refused rather than a second success screen.
    get url
    assert_response :unprocessable_entity

    # After a rotate the old poster is dead.
    @ws.rotate_checkin_nonce!
    get url
    assert_response :unprocessable_entity
    assert_match I18n.t("customer.scan.invalid_message"), response.body
  end

  # A printed poster carries a static token, so the only remedy for a leaked QR
  # is rotating the nonce — which had no way to be triggered.
  test "rotating the check-in nonce invalidates the printed poster" do
    ActsAsTenant.with_tenant(@ws) do
      old = Checkin.encode(@ws, @outlet)
      assert_equal [true, @outlet.id], Checkin.decode(old, workspace: @ws)

      @ws.rotate_checkin_nonce!

      assert_equal [false, nil], Checkin.decode(old, workspace: @ws.reload)
      assert_equal [true, @outlet.id], Checkin.decode(Checkin.encode(@ws, @outlet), workspace: @ws)
    end
  end
end
