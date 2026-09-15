# ---------------------------------------------------------------------------
# Dynamic Loyalty — Phase 0 demo seed
# 3 themed workspaces on one layout (dynamic branding), each with program,
# tiers, an outlet, an owner and demo members. Safe to re-run.
# ---------------------------------------------------------------------------
require "faker"
Faker::Config.locale = "vi"

# ---------------------------------------------------------------------------
# Seed passwords
#
# Every account created below is a real login — the super admin sees every
# workspace, and each shop owner sees that shop's customers and billing. A
# password hard-coded here is a published credential: it lives in the repo, and
# the account names are guessable from the public subdomains. So outside
# development this file refuses to invent one.
#
#   development / test  → the convenience default (or SEED_PASSWORD if given)
#   anywhere else       → SEED_PASSWORD is required, and must be a real password
#
# Seeding is also non-destructive for credentials: a password is only ever set
# on an account this run CREATES. Re-running db:seed never resets a password
# someone has since changed.
# ---------------------------------------------------------------------------
DEV_SEED_PASSWORD = "loyalty1234".freeze
MIN_SEED_PASSWORD = 12

SEED_PASSWORD = begin
  given = ENV["SEED_PASSWORD"].presence
  if Rails.env.development? || Rails.env.test?
    given || DEV_SEED_PASSWORD
  elsif given.nil?
    abort <<~MSG
      ✗ Refusing to seed #{Rails.env}: SEED_PASSWORD is not set.

        This seed creates a super admin and shop owners. Using the built-in
        development password here would publish those logins — it is written in
        plain text in db/seeds.rb.

        Re-run with a password you choose, e.g.

          SEED_PASSWORD='<#{MIN_SEED_PASSWORD}+ characters>' bin/rails db:seed

        Existing accounts keep whatever password they already have.
    MSG
  elsif given.length < MIN_SEED_PASSWORD
    abort "✗ SEED_PASSWORD must be at least #{MIN_SEED_PASSWORD} characters (got #{given.length})."
  elsif given == DEV_SEED_PASSWORD
    abort "✗ SEED_PASSWORD must not be the development default."
  else
    given
  end
end

# Only ever set a password on an account we are creating (see above).
def apply_seed_password(record)
  return record unless record.new_record?
  record.assign_attributes(password: SEED_PASSWORD, password_confirmation: SEED_PASSWORD)
  record
end

# Show the password only for an account this run just created, and only in
# development — printing it for an existing account would be a lie (it may have
# been changed since), and printing it in production would leak it to the log.
def seed_password_hint(created)
  return "" unless created && (Rails.env.development? || Rails.env.test?)
  " / #{SEED_PASSWORD}"
end

puts "Seeding Dynamic Loyalty demo data…"

Plan.seed_defaults!
puts "  ✓ Plans: #{Plan.ordered.map(&:key).join(', ')}"

PRESETS = Merchant::AppearancesController::PRESETS

TIER_TEMPLATE = [
  { key: "bronze",  name: "Đồng",      threshold_points: 0,     multiplier: 1.0, from: "#C08A52", to: "#8A5A2E" },
  { key: "silver",  name: "Bạc",       threshold_points: 2000,  multiplier: 1.2, from: "#C9CDD4", to: "#8A9099" },
  { key: "gold",    name: "Vàng",      threshold_points: 5000,  multiplier: 1.5, from: "#E6C15A", to: "#B8892E" },
  { key: "diamond", name: "Kim Cương", threshold_points: 12000, multiplier: 2.0, from: "#8FD6E8", to: "#4A9FC7" }
].freeze

WORKSPACES = [
  { name: "Mộc Cà Phê",       subdomain: "cozycafe",  industry: "fnb",
    preset: "cozy_cafe",     customer_term: "bạn",       tagline: "Mỗi ly một niềm vui",
    scan_mode: "staff_scans_member", earn_points: 1, earn_per_amount: 10000,
    outlet: "Mộc Cà Phê — Thảo Điền" },
  { name: "Lụa Spa & Beauty", subdomain: "luaspa",    industry: "service",
    preset: "modern_beauty", customer_term: "quý khách", tagline: "Chạm nhẹ, yêu thương",
    scan_mode: "staff_scans_member", earn_points: 1, earn_per_amount: 20000,
    outlet: "Lụa Spa — Quận 1" },
  { name: "Phố Retail",       subdomain: "phoretail", industry: "retail",
    preset: "retail_bold",   customer_term: "Fan cứng",  tagline: "Phong cách của bạn, đặc quyền của bạn",
    scan_mode: "both", earn_points: 1, earn_per_amount: 15000,
    outlet: "Phố Retail — Vincom" }
].freeze

ActsAsTenant.without_tenant do
  # ---- Super Admin -------------------------------------------------------
  admin = AdminUser.find_or_initialize_by(email: "admin@loyalty.vn")
  admin.assign_attributes(name: "Vận hành Nền tảng", role: "superadmin")
  created = admin.new_record?
  apply_seed_password(admin).save!
  puts "  ✓ Super Admin: admin@loyalty.vn#{seed_password_hint(created)}" \
       "#{created ? "" : " (đã có sẵn — mật khẩu giữ nguyên)"}"

  WORKSPACES.each do |cfg|
    ws = Workspace.find_or_initialize_by(subdomain: cfg[:subdomain])
    ws.assign_attributes(
      name: cfg[:name], industry: cfg[:industry], status: "active", plan: "growth",
      locale_default: "vi",
      theme: PRESETS[cfg[:preset]]["theme"],
      branding: { "customer_term" => cfg[:customer_term], "tagline" => cfg[:tagline], "tone" => "friendly" },
      settings: { "onboarded" => true }
    )
    ws.slug ||= cfg[:subdomain]
    ws.save!

    ActsAsTenant.with_tenant(ws) do
      # Loyalty program
      program = ws.loyalty_program || ws.build_loyalty_program
      program.update!(points_enabled: true, tiers_enabled: true,
                      stamps_enabled: cfg[:industry] == "fnb",
                      gamification_enabled: cfg[:industry] != "service",
                      earn_points: cfg[:earn_points], earn_per_amount: cfg[:earn_per_amount],
                      currency: "VND", scan_mode: cfg[:scan_mode], tier_cycle_months: 12)

      # Tiers
      TIER_TEMPLATE.each_with_index do |t, i|
        tier = Tier.find_or_initialize_by(workspace: ws, key: t[:key])
        tier.update!(name: t[:name], threshold_points: t[:threshold_points], multiplier: t[:multiplier],
                     gradient_from: t[:from], gradient_to: t[:to], position: i)
      end

      # Outlet
      outlet = Outlet.find_or_initialize_by(workspace: ws, code: "MAIN")
      outlet.update!(name: cfg[:outlet], address: Faker::Address.street_address, active: true)

      # Rewards catalog (redeemable by points)
      reward_set = {
        "fnb" => [
          { title: "Cà phê sữa đá miễn phí", kind: "voucher", icon: "☕", cost_points: 300, value: 0, value_unit: "item" },
          { title: "Giảm 30% toàn menu trà",  kind: "discount", icon: "🧋", cost_points: 250, value: 30, value_unit: "percent" },
          { title: "Giảm 50.000đ hoá đơn",    kind: "voucher", icon: "🎟️", cost_points: 800, value: 50000, value_unit: "vnd" },
          { title: "Bánh ngọt tặng kèm",      kind: "gift", icon: "🍰", cost_points: 500, value: 0, value_unit: "item", stock: 50 }
        ],
        "service" => [
          { title: "Buổi massage 30 phút",     kind: "voucher", icon: "💆", cost_points: 1200, value: 0, value_unit: "item" },
          { title: "Giảm 20% liệu trình",      kind: "discount", icon: "✨", cost_points: 600, value: 20, value_unit: "percent" },
          { title: "Voucher 100.000đ dịch vụ", kind: "voucher", icon: "🎟️", cost_points: 1000, value: 100000, value_unit: "vnd" }
        ],
        "retail" => [
          { title: "Voucher 100.000đ mua sắm", kind: "voucher", icon: "🛍️", cost_points: 900, value: 100000, value_unit: "vnd" },
          { title: "Giảm 25% một sản phẩm",    kind: "discount", icon: "🏷️", cost_points: 500, value: 25, value_unit: "percent" },
          { title: "Túi tote độc quyền",       kind: "gift", icon: "👜", cost_points: 1500, value: 0, value_unit: "item", stock: 30 }
        ]
      }
      (reward_set[cfg[:industry]] || []).each_with_index do |rw, i|
        reward = Reward.find_or_initialize_by(workspace: ws, title: rw[:title])
        reward.update!(rw.merge(active: true, position: i, valid_days: 30))
      end

      # Gamification (workspaces with it enabled)
      if program.gamification_enabled
        gift_reward = ws.rewards.where(value_unit: "item").first || ws.rewards.first
        if ws.stamp_cards.empty? && gift_reward
          ws.stamp_cards.create!(title: cfg[:industry] == "fnb" ? "Mua 9 ly tặng 1" : "Mua 5 lần tặng quà",
                                 description: "Tích tem cho mỗi lần mua", icon: cfg[:industry] == "fnb" ? "🧋" : "🛍️",
                                 target_count: cfg[:industry] == "fnb" ? 9 : 5, reward: gift_reward, active: true)
        end
        if ws.missions.empty?
          ws.missions.create!(title: "Check-in hôm nay", icon: "📍", mission_type: "checkin", period: "daily", goal: 1, reward_points: 20, position: 0)
          ws.missions.create!(title: "Ghé 3 lần trong tuần", icon: "🏪", mission_type: "visit", period: "weekly", goal: 3, reward_points: 50, position: 1)
          ws.missions.create!(title: "Chi tiêu 100.000đ hôm nay", icon: "💳", mission_type: "spend", period: "daily", goal: 100000, reward_points: 30, position: 2)
        end
        if ws.badges.empty?
          [["newbie", "Người mới", "Mua hàng lần đầu", "🌱", "first_purchase", 1],
           ["regular", "Khách quen", "Mua đủ 10 lần", "☕", "purchases_count", 10],
           ["collector", "Cao thủ điểm", "Tích luỹ 5.000 điểm", "💎", "points_total", 5000],
           ["nightowl", "Cú đêm", "Mua sau 22h", "🦉", "night_owl", 1]].each_with_index do |(k, n, d, ic, ct, th), i|
            ws.badges.create!(key: k, name: n, description: d, icon: ic, criteria_type: ct, threshold: th, position: i)
          end
        end
        ws.create_spin_wheel!(segments: SpinWheel::DEFAULT_SEGMENTS.map(&:stringify_keys), daily_free: true, cost_points: 100, active: true) unless ws.spin_wheel
      end

      # Demo campaign + shared promo QR (claim-to-wallet)
      promo_reward = ws.rewards.redeemable.first
      if promo_reward && ws.campaigns.empty?
        camp = ws.campaigns.create!(
          name: "Khai trương — tặng #{promo_reward.title}", campaign_type: "promo_voucher",
          audience: "all", status: "running", starts_at: Time.current, ends_at: 30.days.from_now,
          content: { "title" => "Quà tặng khai trương 🎉", "body" => "Quét mã nhận ngay #{promo_reward.title}, không tốn điểm!" }
        )
        ws.promo_codes.create!(campaign: camp, reward: promo_reward, max_claims: 200,
                               starts_at: camp.starts_at, ends_at: camp.ends_at, active: true)
      end

      # Owner + membership
      owner_email = "owner@#{cfg[:subdomain]}.vn"
      owner = User.find_or_initialize_by(email: owner_email)
      owner.assign_attributes(name: "Chủ #{cfg[:name]}", title: "Chủ cửa hàng", locale: "vi")
      owner_created = owner.new_record?
      apply_seed_password(owner).save!
      Membership.find_or_create_by!(user: owner, workspace: ws) do |m|
        m.role = "owner"; m.outlet = outlet
      end

      # Demo members with a real point ledger (earn transactions from purchases)
      6.times do |n|
        phone = "09#{format('%08d', ws.id * 1_000_000 + n)}"
        member = Member.find_or_initialize_by(workspace: ws, phone: phone)
        # Login is email + OTP, so a demo member without one can be seen on the
        # merchant dashboard but never signed into — which is exactly the account
        # you want when testing the customer app against a real points history.
        member.assign_attributes(name: Faker::Name.name,
                                 birthday: Faker::Date.birthday(min_age: 18, max_age: 55))
        member.email ||= "khach#{n + 1}@#{cfg[:subdomain]}.vn"
        member.save!

        if member.point_transactions.empty?
          target = [120, 850, 2400, 3300, 6200, 15000][n] || rand(100..8000)
          # split into 2–4 earns over the last ~90 days
          chunks = [target / 3, target / 3, target - 2 * (target / 3)].reject(&:zero?)
          chunks.each_with_index do |pts, i|
            amount = pts * program.earn_per_amount / program.earn_points
            created = Faker::Time.between(from: 90.days.ago, to: 2.days.ago)
            purchase = Purchase.create!(workspace: ws, member: member, outlet: outlet,
                                        amount: amount, points_earned: pts, source: "staff_scan",
                                        created_at: created, updated_at: created)
            PointTransaction.create!(workspace: ws, member: member, kind: "earn", amount: pts,
                                     source: purchase, outlet: outlet,
                                     created_at: created, updated_at: created)
          end
          member.recompute_points!
        end
      end
      # Demo notifications for the first member + a referral pair
      members = ws.members.order(:id).to_a
      if members.any? && members.first.notifications.empty?
        m0 = members.first
        Notification.create!(workspace: ws, member: m0, kind: "promo", icon: "🎁",
                             title: "Ưu đãi cuối tuần cho #{cfg[:customer_term]}!",
                             body: "Nhân đôi điểm cho mọi hoá đơn từ thứ 6 đến chủ nhật.")
        Notification.create!(workspace: ws, member: m0, kind: "reminder", icon: "⏰",
                             title: "Đã lâu chưa gặp lại!", body: "Ghé cửa hàng tuần này để nhận quà nhé.")
      end
      if members.size >= 2 && Referral.where(referrer: members[0]).none?
        members[1].update!(referred_by: members[0])
        Referral.create!(workspace: ws, referrer: members[0], referred: members[1],
                         state: "completed", reward_points: ws.program.referral_points, completed_at: 3.days.ago)
      end

      puts "  ✓ #{cfg[:name]} (#{cfg[:subdomain]}) — #{owner_email}#{seed_password_hint(owner_created)}" \
           "#{owner_created ? "" : " (đã có sẵn)"}, #{ws.members.count} members"
    end
  end
end

ActsAsTenant.without_tenant do
  # A pending workspace to demo the Super Admin approval queue.
  pending = Workspace.find_or_initialize_by(subdomain: "tiembanhngot")
  if pending.new_record?
    pending.assign_attributes(name: "Tiệm Bánh Ngọt", industry: "fnb", status: "pending", plan: "starter",
                              theme: PRESETS["cozy_cafe"]["theme"],
                              branding: { "customer_term" => "bạn", "tagline" => "Ngọt ngào mỗi ngày" })
    pending.slug ||= "tiembanhngot"
    pending.save!
    owner = User.find_or_initialize_by(email: "owner@tiembanhngot.vn")
    owner.assign_attributes(name: "Chủ Tiệm Bánh", locale: "vi") if owner.new_record?
    apply_seed_password(owner).save!
    ActsAsTenant.with_tenant(pending) { pending.memberships.find_or_create_by!(user: owner) { |m| m.role = "owner" } }
    WorkspaceBootstrap.call(pending)
    puts "  ✓ Tiệm Bánh Ngọt (pending) — chờ Super Admin duyệt"
  end
end

ActsAsTenant.without_tenant do
  puts "Done. #{Workspace.count} workspaces · #{Member.count} members. Merchant: /merchant · Admin: /admin"
end
