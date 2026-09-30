# Sets up sensible defaults for a freshly created workspace (program, tiers,
# lucky wheel) so the merchant dashboard and customer app work immediately.
module WorkspaceBootstrap
  module_function

  # Gold is sampled from the design's tier crest; the other three are cut in the
  # same register — saturated, with a genuinely deep bottom stop so the badge
  # holds its lettering. Merchants can change all of them, so these are only the
  # starting point (see Tier#ink_color, which keeps the text readable whatever
  # they pick).
  # `from`/`to` are the crest gradient; `pill_*` are the badge, both sampled
  # from the design. They are deliberately different palettes — the crest is
  # saturated, the badge is a soft tint with coloured lettering.
  TIERS = [
    { key: "bronze",  name: "Đồng",      threshold_points: 0,     multiplier: 1.0,
      from: "#C87A34", to: "#8A4310", pill_bg: "#FCEED8", pill_fg: "#AC6E55" },
    { key: "silver",  name: "Bạc",       threshold_points: 2000,  multiplier: 1.2,
      from: "#C2CBD6", to: "#6E7B8A", pill_bg: "#F2F5F9", pill_fg: "#97A2B6" },
    { key: "gold",    name: "Vàng",      threshold_points: 5000,  multiplier: 1.5,
      from: "#F6B51F", to: "#DD7F09", pill_bg: "#FCF3CC", pill_fg: "#B76041", pill_border: "#CC7C2E" },
    { key: "diamond", name: "Kim Cương", threshold_points: 12000, multiplier: 2.0,
      from: "#7FC8E8", to: "#2F7FB5", pill_bg: "#FAF2EE", pill_fg: "#2C241C" }
  ].freeze

  EARN = { "fnb" => 10_000, "retail" => 15_000, "service" => 20_000 }.freeze

  def call(workspace)
    ActsAsTenant.with_tenant(workspace) do
      program = workspace.loyalty_program || workspace.build_loyalty_program
      program.update!(points_enabled: true, tiers_enabled: true,
                      stamps_enabled: workspace.industry == "fnb",
                      gamification_enabled: workspace.industry != "service",
                      earn_points: 1, earn_per_amount: EARN[workspace.industry] || 10_000,
                      currency: "VND", scan_mode: "staff_scans_member")

      TIERS.each_with_index do |t, i|
        next if workspace.tiers.exists?(key: t[:key])
        workspace.tiers.create!(name: t[:name], key: t[:key], threshold_points: t[:threshold_points],
                                multiplier: t[:multiplier], gradient_from: t[:from], gradient_to: t[:to],
                                pill_bg: t[:pill_bg], pill_fg: t[:pill_fg], pill_border: t[:pill_border],
                                position: i)
      end

      if program.gamification_enabled && workspace.spin_wheel.nil?
        workspace.create_spin_wheel!(segments: SpinWheel::DEFAULT_SEGMENTS.map(&:stringify_keys),
                                     daily_free: true, cost_points: 100, active: true)
      end

      # A default check-in mission so the branch check-in QR awards points from
      # day one (merchants can edit/remove it later).
      if program.gamification_enabled && !workspace.missions.exists?(mission_type: "checkin")
        workspace.missions.create!(title: "Check-in hôm nay", icon: "📍", mission_type: "checkin",
                                   period: "daily", goal: 1, reward_points: 20, position: 0)
      end
    end

    # Every shop needs at least one branch — the check-in QR lives on branches.
    workspace.ensure_default_outlet!
    workspace
  end
end
