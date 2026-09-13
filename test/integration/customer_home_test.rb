require "test_helper"

# The shop's front screen: the first thing a customer sees, in whichever
# language they picked.
class CustomerHomeTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "homews")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      @prog = create(:loyalty_program, workspace: @ws, gamification_enabled: true,
                     points_expiry_months: 6, earn_points: 1, earn_per_amount: 10_000)
      @member = create(:member, workspace: @ws, email: "home@example.com")
      @member.point_transactions.create!(workspace: @ws, kind: "earn", amount: 900,
                                         expires_at: 10.days.from_now)
      @member.recompute_points!
      @reward = create(:reward, workspace: @ws, cost_points: 100, title: "Cà phê")
    end
    sign_in_member!
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member!
    post "#{base}/login", params: { email: @member.email }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email, purpose: "login").order(:id).last
    post "#{base}/verify", params: { code: ch.code }
  end

  # Three strings on this screen were written straight into the markup in
  # Vietnamese, and two more used t(..., default: "…") with a Vietnamese
  # fallback for a key that did not exist — so an English customer got a
  # Vietnamese home screen and nothing flagged it.
  test "the home screen is fully translated in English" do
    get "#{base}?locale=en"
    assert_response :success

    body = response.body
    refute_match "điểm sẽ hết hạn", body
    refute_match "đổi ngay", body
    refute_match "Đổi ngay", body
    refute_match(/translation missing/i, body)
    assert_match "expire", body, "the expiry warning is shown, in English"
  end

  test "the home screen still reads correctly in Vietnamese" do
    get base
    assert_response :success
    assert_match "sẽ hết hạn", response.body
    refute_match(/translation missing/i, response.body)
  end

  # "Nhiệm vụ hôm nay" showed the first three by position whether or not they
  # were done, so a customer who had finished them was shown three ticked boxes
  # and none of the ones still worth doing.
  test "missions still to do are the ones surfaced" do
    done_ids = []
    ActsAsTenant.with_tenant(@ws) do
      5.times do |i|
        m = @ws.missions.create!(title: "NV #{i}", mission_type: "checkin", goal: 1,
                                 reward_points: 10, active: true, position: i, period: "daily")
        if i < 3 # the first three by position are already finished
          mp = m.progress_for(@member)
          mp.save!
          mp.update!(progress: 1, completed_at: Time.current, claimed_at: Time.current)
          done_ids << m.id
        end
      end
    end

    get base
    assert_response :success
    assert_match "NV 3", response.body
    assert_match "NV 4", response.body
  end

  # Each mission looked its own progress row up one at a time.
  test "the mission list does not query per mission" do
    ActsAsTenant.with_tenant(@ws) do
      8.times { |i| @ws.missions.create!(title: "NV #{i}", mission_type: "checkin", goal: 1,
                                         reward_points: 10, active: true, position: i, period: "daily") }
    end
    n = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      n += 1 if payload[:sql].to_s.include?('FROM "mission_progresses"')
    end
    get base
    ActiveSupport::Notifications.unsubscribe(sub)
    assert_response :success
    assert n <= 2, "expected one lookup for all missions, got #{n}"
  end
end
