require "test_helper"

# The programme config page writes the rules every other screen computes from,
# so bad input here corrupts tiers, points and the customer PWA rather than just
# failing a form.
class LoyaltyProgramConfigTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace)
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @owner = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      @program = create(:loyalty_program, workspace: @ws, earn_points: 1, earn_per_amount: 10_000)
      @ws.memberships.create!(user: @owner, role: "owner")
      WorkspaceBootstrap::TIERS.each_with_index do |t, i|
        @ws.tiers.create!(key: t[:key], name: t[:name], threshold_points: t[:threshold_points],
                          multiplier: t[:multiplier], gradient_from: t[:from], gradient_to: t[:to], position: i)
      end
      @member = create(:member, workspace: @ws)
      @member.point_transactions.create!(workspace: @ws, kind: "earn", amount: 6_000)
      @member.recompute_points!
    end
    sign_in @owner
  end

  def tier(key) = ActsAsTenant.with_tenant(@ws) { @ws.tiers.find_by(key: key) }

  def tier_rows(overrides = {})
    ActsAsTenant.with_tenant(@ws) do
      @ws.tiers.ordered.index_with do |t|
        { name: t.name, threshold_points: t.threshold_points, multiplier: t.multiplier,
          benefits: "", gradient_from: t.gradient_from, gradient_to: t.gradient_to }
      end.transform_keys { |t| t.id.to_s }.tap { |h| overrides.each { |k, v| h[tier(k).id.to_s].merge!(v) } }
    end
  end

  # A tier cycle of 0 months made cycle_points count only transactions created
  # this instant, so every customer in the shop silently dropped to the bottom
  # tier. The field had no minimum, so it was one keystroke away in the form.
  test "tier cycle of zero months is rejected" do
    assert_equal "gold", ActsAsTenant.with_tenant(@ws) { @member.reload.tier_for(@member.cycle_points).key }

    patch merchant_loyalty_program_path, params: { loyalty_program: { tier_cycle_months: 0 } }
    assert_response :unprocessable_entity
    assert_equal 12, @program.reload.tier_cycle_months
    # …and the page has to say why, with the tier grid still on it.
    assert_match "Chu kỳ xét hạng", response.body
    assert_match "Kim Cương", response.body

    ActsAsTenant.with_tenant(@ws) do
      assert_equal 6_000, @member.reload.cycle_points
      assert_equal "gold", @member.tier_for(@member.cycle_points).key
    end
  end

  # numeric(4,2) and int4 both overflow before any validation ran, so these came
  # back as a 500 page rather than a field error.
  test "out-of-range tier numbers are refused, not crashed on" do
    patch merchant_tiers_path, params: { tiers: tier_rows("diamond" => { multiplier: 100 }) }
    assert_redirected_to merchant_loyalty_program_path
    assert_match(/hệ số/i, flash[:alert].to_s)
    assert_equal 2.0, tier("diamond").multiplier.to_f

    patch merchant_tiers_path, params: { tiers: tier_rows("diamond" => { threshold_points: 99_999_999_999 }) }
    assert_redirected_to merchant_loyalty_program_path
    assert_equal 12_000, tier("diamond").threshold_points
  end

  # gradient_css is interpolated straight into style="background:…" on three
  # customer PWA pages. Anything but a colour there injects CSS — including a
  # url() that fires a request from the customer's browser.
  test "tier colours must be hex" do
    patch merchant_tiers_path, params: {
      tiers: tier_rows("gold" => { gradient_from: "red; background-image:url(https://evil.example/x)" })
    }
    assert_redirected_to merchant_loyalty_program_path
    assert_equal "#E6C15A", tier("gold").gradient_from
    refute_includes tier("gold").gradient_css, "evil.example"
  end

  # Thresholds that don't climb with position broke next_tier: a bronze member
  # was told the next rung was silver at 2.000 when gold at 1.000 came first, so
  # "còn X điểm nữa" and the progress bar both lied.
  test "thresholds must increase with tier position" do
    patch merchant_tiers_path, params: { tiers: tier_rows("gold" => { threshold_points: 1_000 }) }
    assert_redirected_to merchant_loyalty_program_path
    assert_match(/mốc điểm/i, flash[:alert].to_s)
    assert_equal 5_000, tier("gold").threshold_points
  end

  # Every row was written with its return value dropped, so a refused save still
  # reported "Đã lưu cấu hình".
  test "a refused tier edit does not report success" do
    patch merchant_tiers_path, params: { tiers: tier_rows("silver" => { multiplier: 100 }) }
    assert_nil flash[:notice]
    assert flash[:alert].present?
  end

  # Plan-gated mechanisms were accepted by the form and forced back off on save,
  # so a starter merchant got "Đã lưu cấu hình chương trình." next to a toggle
  # that had flipped itself back with nothing to explain it.
  test "a plan-locked mechanism says so instead of reporting success" do
    Plan.seed_defaults! if Plan.none?
    @ws.update!(status: "active", plan: "starter")
    refute @ws.plan_allows?(:gamification)

    patch merchant_loyalty_program_path,
          params: { loyalty_program: { gamification_enabled: "1", tier_cycle_months: 6 } }

    assert_redirected_to merchant_loyalty_program_path
    assert_nil flash[:notice]
    assert_match(/Gamification/, flash[:alert].to_s)
    refute @program.reload.gamification_enabled
    assert_equal 6, @program.tier_cycle_months, "the rest of the form still saved"

    follow_redirect!
    assert_select "input[name=?][disabled='disabled']", "loyalty_program[gamification_enabled]"

    # A disabled toggle submits nothing, so an ordinary save of this page must
    # not keep nagging about a feature the merchant never touched.
    patch merchant_loyalty_program_path, params: { loyalty_program: { tier_cycle_months: 9 } }
    assert_nil flash[:alert]
    assert flash[:notice].present?
  end

  test "a valid edit still saves every row" do
    patch merchant_tiers_path, params: {
      tiers: tier_rows("silver" => { threshold_points: 2_500, multiplier: 1.3,
                                     benefits: "Giảm 10%\nƯu tiên chỗ ngồi", gradient_from: "#123456" })
    }
    assert_redirected_to merchant_loyalty_program_path
    assert_equal "Đã lưu", flash[:notice].to_s[0, 6]
    t = tier("silver")
    assert_equal 2_500, t.threshold_points
    assert_equal 1.3, t.multiplier.to_f
    assert_equal ["Giảm 10%", "Ưu tiên chỗ ngồi"], t.benefits
    assert_equal "#123456", t.gradient_from
  end
end
