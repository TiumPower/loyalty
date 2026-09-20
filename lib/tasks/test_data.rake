# Rebuilds the whole demo/test dataset from scratch.
#
#   bin/rails loyalty:test_data PASSWORD='...'            # dev
#   cap production deploy:test_data                       # production wrapper
#
# Destructive by design: every workspace (and everything inside it) is deleted,
# then rebuilt. AdminUser rows are KEPT — only the super admin's password is
# reset to PASSWORD so the account stays usable for testing.
namespace :loyalty do
  desc "Wipe all workspaces and rebuild a full test dataset (every role, every state). ENV: PASSWORD, CONFIRM"
  task test_data: :environment do
    require "faker"
    Faker::Config.locale = "vi"

    password = ENV["PASSWORD"].to_s.dup.force_encoding("UTF-8").presence ||
               abort("✗ Cần PASSWORD='<mật khẩu ≥12 ký tự>'.")
    abort("✗ PASSWORD phải dài ít nhất 12 ký tự (đang #{password.length}).") if password.length < 12
    if Rails.env.production? && ENV["CONFIRM"] != "yes"
      abort("✗ Production: chạy lại với CONFIRM=yes để xác nhận XOÁ toàn bộ workspace hiện có.")
    end

    ADMIN_EMAIL = "admin@loyalty.vn".freeze

    SHOPS = [
      { sub: "cozycafe", name: "Mộc Cà Phê", industry: "fnb", preset: "cozy_cafe", plan: "growth",
        term: "bạn", tagline: "Mỗi ly một niềm vui", scan_mode: "staff_scans_member", earn_per: 10_000,
        outlets: [["MAIN", "Mộc Cà Phê — Thảo Điền", "12 Nguyễn Ư Dĩ, Thảo Điền, TP. Thủ Đức"],
                  ["D1",   "Mộc Cà Phê — Quận 1",    "45 Lý Tự Trọng, Bến Nghé, Quận 1"],
                  ["GV",   "Mộc Cà Phê — Gò Vấp",    "88 Quang Trung, Phường 10, Gò Vấp"]],
        rewards: [
          { title: "Cà phê sữa đá miễn phí", kind: "voucher",  icon: "☕", cost_points: 300,  value: 0,     value_unit: "item" },
          { title: "Giảm 30% toàn menu trà", kind: "discount", icon: "🧋", cost_points: 250,  value: 30,    value_unit: "percent" },
          { title: "Giảm 50.000đ hoá đơn",   kind: "voucher",  icon: "🎟️", cost_points: 800,  value: 50000, value_unit: "vnd" },
          { title: "Bánh ngọt tặng kèm",     kind: "gift",     icon: "🍰", cost_points: 500,  value: 0,     value_unit: "item", stock: 50 },
          { title: "Combo 2 ly + bánh",      kind: "voucher",  icon: "🥐", cost_points: 1200, value: 0,     value_unit: "item" }
        ],
        stamp: ["Mua 9 ly tặng 1", "Tích 1 tem mỗi ly, đủ 9 tem đổi 1 ly miễn phí", "🧋", 9],
        reviews: [[5, "Cà phê ngon, không gian ấm cúng, nhân viên dễ thương!"],
                  [5, "Tích điểm đổi quà tiện lắm, tuần nào cũng ghé."],
                  [4, "Bánh ngọt ổn, chỗ ngồi hơi ít vào giờ cao điểm."],
                  [2, "Hôm qua đợi hơi lâu, mong shop cải thiện."]] },

      { sub: "luaspa", name: "Lụa Spa & Beauty", industry: "service", preset: "modern_beauty", plan: "scale",
        term: "quý khách", tagline: "Chạm nhẹ, yêu thương", scan_mode: "staff_scans_member", earn_per: 20_000,
        outlets: [["MAIN", "Lụa Spa — Quận 1",   "18 Lê Thánh Tôn, Bến Nghé, Quận 1"],
                  ["PN",   "Lụa Spa — Phú Nhuận", "202 Phan Xích Long, Phú Nhuận"]],
        rewards: [
          { title: "Buổi massage 30 phút",     kind: "voucher",  icon: "💆", cost_points: 1200, value: 0,      value_unit: "item" },
          { title: "Giảm 20% liệu trình",      kind: "discount", icon: "✨", cost_points: 600,  value: 20,     value_unit: "percent" },
          { title: "Voucher 100.000đ dịch vụ", kind: "voucher",  icon: "🎟️", cost_points: 1000, value: 100000, value_unit: "vnd" },
          { title: "Quà sinh nhật đặc biệt",   kind: "gift",     icon: "🎂", cost_points: 0,    value: 0,      value_unit: "item", stock: 100 }
        ],
        stamp: nil,
        reviews: [[5, "Kỹ thuật viên nhẹ nhàng, rất thư giãn."],
                  [5, "Đặt lịch nhanh, đổi voucher tiện."],
                  [4, "Giá hơi cao nhưng chất lượng xứng đáng."]] },

      { sub: "phoretail", name: "Phố Retail", industry: "retail", preset: "retail_bold", plan: "starter",
        term: "Fan cứng", tagline: "Phong cách của bạn, đặc quyền của bạn", scan_mode: "both", earn_per: 15_000,
        outlets: [["MAIN", "Phố Retail — Vincom Đồng Khởi", "72 Lê Thánh Tôn, Bến Nghé, Quận 1"],
                  ["CRE",  "Phố Retail — Crescent Mall",    "101 Tôn Dật Tiên, Tân Phú, Quận 7"]],
        rewards: [
          { title: "Voucher 100.000đ mua sắm", kind: "voucher",  icon: "🛍️", cost_points: 900,  value: 100000, value_unit: "vnd" },
          { title: "Giảm 25% một sản phẩm",    kind: "discount", icon: "🏷️", cost_points: 500,  value: 25,     value_unit: "percent" },
          { title: "Túi tote độc quyền",       kind: "gift",     icon: "👜", cost_points: 1500, value: 0,      value_unit: "item", stock: 30 }
        ],
        stamp: ["Mua 5 lần tặng quà", "Mỗi hoá đơn 1 tem, đủ 5 tem nhận quà", "🛍️", 5],
        reviews: [[5, "Săn sale mà còn tích điểm, quá hời."],
                  [3, "Nhân viên đông khách nên hơi chậm."],
                  [5, "Túi tote đổi bằng điểm xịn hơn mong đợi."]] }
    ].freeze

    STAFF = [
      { role: "owner",   prefix: "owner",    name: "Chủ cửa hàng",  title: "Chủ cửa hàng" },
      { role: "manager", prefix: "quanly",   name: "Quản lý",       title: "Quản lý cửa hàng" },
      { role: "staff",   prefix: "nhanvien", name: "Nhân viên",     title: "Nhân viên phục vụ" },
      { role: "cashier", prefix: "thungan",  name: "Thu ngân",      title: "Thu ngân" }
    ].freeze

    # Points target per demo member → spreads them across every tier, plus a
    # brand-new member (0 điểm) and one with a birthday today.
    MEMBER_TARGETS = [0, 120, 850, 2_400, 3_300, 6_200, 9_500, 15_000].freeze

    ActsAsTenant.without_tenant do
      puts "⚠  Xoá toàn bộ workspace hiện có…"
      # Xoá theo đúng thứ tự phụ thuộc: các bảng con trỏ tới outlets/members
      # phải đi trước, vì `workspace.destroy` huỷ outlets trước members.
      child_tables = %w[PointTransaction SpinLog MemberBadge MissionProgress StampCardMembership
                        PromoClaim Voucher Purchase PosCharge Rating Notification Referral
                        PushSubscription Broadcast MerchantAlert WorkspaceInsight
                        PromoCode Campaign StampCard OtpChallenge Invoice]
      Workspace.find_each do |ws|
        ActsAsTenant.with_tenant(ws) do
          child_tables.each do |name|
            klass = name.safe_constantize or next
            klass.where(workspace_id: ws.id).delete_all
          end
          ws.destroy!
        end
      end
      User.left_joins(:memberships).where(memberships: { id: nil }).destroy_all
      puts "   ✓ Đã xoá. Còn #{Workspace.count} workspace, #{User.count} user, #{Member.count} member."

      Plan.seed_defaults!

      admin = AdminUser.find_or_initialize_by(email: ADMIN_EMAIL)
      admin.assign_attributes(name: "Vận hành Nền tảng", role: "superadmin",
                              password: password, password_confirmation: password)
      admin.save!
      puts "   ✓ Super Admin #{ADMIN_EMAIL} (đặt lại mật khẩu)"

      presets = Merchant::AppearancesController::PRESETS

      SHOPS.each do |cfg|
        ws = Workspace.create!(
          name: cfg[:name], subdomain: cfg[:sub], slug: cfg[:sub], industry: cfg[:industry],
          status: "active", plan: cfg[:plan], locale_default: "vi",
          paid_until: Time.current.end_of_month.end_of_day,
          theme: presets[cfg[:preset]]["theme"],
          branding: { "customer_term" => cfg[:term], "tagline" => cfg[:tagline], "tone" => "friendly" },
          settings: { "onboarded" => true, "feedback_public" => true }
        )

        ActsAsTenant.with_tenant(ws) do
          WorkspaceBootstrap.call(ws)
          program = ws.loyalty_program
          program.update!(earn_points: 1, earn_per_amount: cfg[:earn_per], scan_mode: cfg[:scan_mode],
                          stamps_enabled: cfg[:stamp].present?,
                          gamification_enabled: cfg[:industry] != "service",
                          referral_enabled: true, referral_points: 100)

          # ---- Outlets ---------------------------------------------------
          ws.outlets.destroy_all
          outlets = cfg[:outlets].map { |code, nm, addr| Outlet.create!(workspace: ws, code: code, name: nm, address: addr, active: true) }
          main = outlets.first

          # ---- Staff: một tài khoản cho MỖI vai trò ----------------------
          STAFF.each do |st|
            u = User.find_or_initialize_by(email: "#{st[:prefix]}@#{cfg[:sub]}.vn")
            u.assign_attributes(name: "#{st[:name]} #{cfg[:name]}", title: st[:title], locale: "vi",
                                password: password, password_confirmation: password)
            u.save!
            Membership.find_or_create_by!(user: u, workspace: ws) { |m| m.role = st[:role]; m.outlet = main }
          end

          # ---- Rewards ---------------------------------------------------
          rewards = cfg[:rewards].each_with_index.map do |rw, i|
            Reward.create!(rw.merge(workspace: ws, active: true, position: i, valid_days: 30))
          end

          # ---- Gamification ----------------------------------------------
          if cfg[:stamp]
            title, desc, icon, target = cfg[:stamp]
            gift = rewards.find { |r| r.value_unit == "item" } || rewards.first
            ws.stamp_cards.create!(title: title, description: desc, icon: icon, target_count: target,
                                   reward: gift, active: true)
          end
          if program.gamification_enabled
            ws.missions.where(mission_type: "visit").destroy_all
            ws.missions.create!(title: "Ghé 3 lần trong tuần", icon: "🏪", mission_type: "visit", period: "weekly",
                                goal: 3, reward_points: 50, position: 1)
            ws.missions.create!(title: "Chi tiêu 100.000đ hôm nay", icon: "💳", mission_type: "spend", period: "daily",
                                goal: 100_000, reward_points: 30, position: 2)
            [["newbie", "Người mới", "Mua hàng lần đầu", "🌱", "first_purchase", 1],
             ["regular", "Khách quen", "Mua đủ 10 lần", "☕", "purchases_count", 10],
             ["collector", "Cao thủ điểm", "Tích luỹ 5.000 điểm", "💎", "points_total", 5000],
             ["nightowl", "Cú đêm", "Mua sau 22h", "🦉", "night_owl", 1]].each_with_index do |(k, n, d, ic, ct, th), i|
              ws.badges.create!(key: k, name: n, description: d, icon: ic, criteria_type: ct, threshold: th, position: i)
            end
          end

          # ---- Campaigns + promo QR --------------------------------------
          first_reward = rewards.first
          camp = ws.campaigns.create!(name: "Khai trương — tặng #{first_reward.title}", campaign_type: "promo_voucher",
                                      audience: "all", status: "running", starts_at: Time.current, ends_at: 30.days.from_now,
                                      content: { "title" => "Quà khai trương 🎉",
                                                 "body" => "Quét mã nhận ngay #{first_reward.title} — không tốn điểm!" })
          ws.promo_codes.create!(campaign: camp, reward: first_reward, max_claims: 300,
                                 starts_at: camp.starts_at, ends_at: camp.ends_at, active: true)
          ws.campaigns.create!(name: "Happy Hour cuối tuần", campaign_type: "double_points", audience: "all",
                               status: "running", starts_at: Time.current, ends_at: 60.days.from_now,
                               content: { "title" => "Nhân đôi điểm cuối tuần ⚡", "body" => "Mọi hoá đơn thứ 6–CN được x2 điểm." })
          ws.campaigns.create!(name: "Tri ân khách VIP", campaign_type: "promo_voucher", audience: "vip",
                               status: "scheduled", starts_at: 7.days.from_now, ends_at: 37.days.from_now,
                               content: { "title" => "Đặc quyền hạng Vàng/Kim Cương 👑", "body" => "Quà tặng riêng cho khách thân thiết." })

          # ---- Members: email đoán được để đăng nhập bằng OTP -------------
          members = MEMBER_TARGETS.each_with_index.map do |target, n|
            birthday = n == 2 ? Date.current.change(year: 1995) : Faker::Date.birthday(min_age: 18, max_age: 55)
            m = Member.create!(workspace: ws, name: Faker::Name.name,
                               email: "khach#{n + 1}@#{cfg[:sub]}.vn",
                               phone: "09#{format('%08d', ws.id * 1_000_000 + n)}",
                               birthday: birthday,
                               join_source: Member::JOIN_SOURCES[n % Member::JOIN_SOURCES.size])
            next m if target.zero?

            outlet = outlets.sample
            chunks = [target / 3, target / 3, target - 2 * (target / 3)].reject(&:zero?)
            # Khách cuối cùng để "lâu không quay lại" (dữ liệu cho win-back).
            window = n == MEMBER_TARGETS.size - 1 ? [180, 120] : [90, 1]
            chunks.each do |pts|
              amt = pts * program.earn_per_amount / program.earn_points
              at  = Faker::Time.between(from: window[0].days.ago, to: window[1].days.ago)
              pur = Purchase.create!(workspace: ws, member: m, outlet: outlet, amount: amt, points_earned: pts,
                                     source: "staff_scan", created_at: at, updated_at: at)
              PointTransaction.create!(workspace: ws, member: m, kind: "earn", amount: pts, source: pur,
                                       outlet: outlet, created_at: at, updated_at: at)
            end
            m.recompute_points!
            m
          end

          # ---- Ví voucher: còn hạn · đã dùng · sắp hết hạn ----------------
          redeemable = rewards.select { |r| r.cost_points.to_i.positive? }
          used_count = 0
          members.select { |m| m.points_balance >= 300 }.each_with_index do |m, i|
            reward = redeemable.select { |r| r.cost_points <= m.points_balance }.min_by(&:cost_points)
            next unless reward
            res = RedeemReward.new(member: m, reward: reward).call
            v = res.respond_to?(:voucher) ? res.voucher : nil
            next unless v
            case i % 3
            when 0 then v.update!(state: "used", used_at: rand(1..20).days.ago, used_outlet: main); used_count += 1
            when 1 then v.update!(expires_at: 3.days.from_now) # sắp hết hạn
            end
          end

          # ---- Đánh giá, thông báo, giới thiệu bạn ------------------------
          cfg[:reviews].each_with_index do |(stars, comment), i|
            next unless members[i]
            Rating.create!(workspace: ws, member: members[i], outlet: outlets.sample, stars: stars, comment: comment,
                           created_at: Faker::Time.between(from: 40.days.ago, to: 1.day.ago))
          end
          m0 = members[1]
          Notification.create!(workspace: ws, member: m0, kind: "promo", icon: "🎁",
                               title: "Ưu đãi cuối tuần cho #{cfg[:term]}!",
                               body: "Nhân đôi điểm cho mọi hoá đơn từ thứ 6 đến chủ nhật.")
          Notification.create!(workspace: ws, member: m0, kind: "reminder", icon: "⏰",
                               title: "Đã lâu chưa gặp lại!", body: "Ghé cửa hàng tuần này để nhận quà nhé.")
          members[2].update!(referred_by: members[1])
          Referral.create!(workspace: ws, referrer: members[1], referred: members[2], state: "completed",
                           reward_points: program.referral_points, completed_at: 3.days.ago)

          # ---- Hoá đơn thuê bao nền tảng ---------------------------------
          price = Plan.for(ws.plan).price
          (1..3).each do |i|
            mth = Date.current.beginning_of_month - i.months
            ws.invoices.create!(plan: ws.plan, amount: price, status: "paid",
                                payos_order_code: 71_000_000_000 + ws.id * 1_000 + i,
                                period_start: mth, period_end: mth.end_of_month, paid_at: mth + 3.days)
          end
          cm = Date.current.beginning_of_month
          ws.invoices.create!(plan: ws.plan, amount: price, status: "pending",
                              payos_order_code: 71_000_000_000 + ws.id * 1_000 + 99,
                              period_start: cm, period_end: cm.end_of_month)

          puts "   ✓ #{cfg[:name]} (#{cfg[:sub]}) — #{outlets.size} chi nhánh · #{STAFF.size} nhân sự · " \
               "#{ws.members.count} khách · #{Voucher.where(workspace_id: ws.id).count} voucher (#{used_count} đã dùng) · " \
               "#{ws.campaigns.count} chiến dịch"
        end
      end

      # ---- Shop đang chờ duyệt (để test hàng đợi duyệt của Super Admin) --
      pending = Workspace.create!(name: "Tiệm Bánh Ngọt", subdomain: "tiembanhngot", slug: "tiembanhngot",
                                  industry: "fnb", status: "pending", plan: "starter",
                                  theme: presets["cozy_cafe"]["theme"],
                                  branding: { "customer_term" => "bạn", "tagline" => "Ngọt ngào mỗi ngày" })
      owner = User.find_or_initialize_by(email: "owner@tiembanhngot.vn")
      owner.assign_attributes(name: "Chủ Tiệm Bánh Ngọt", title: "Chủ cửa hàng", locale: "vi",
                              password: password, password_confirmation: password)
      owner.save!
      ActsAsTenant.with_tenant(pending) do
        pending.memberships.find_or_create_by!(user: owner) { |m| m.role = "owner" }
      end
      WorkspaceBootstrap.call(pending)
      puts "   ✓ Tiệm Bánh Ngọt (tiembanhngot) — trạng thái CHỜ DUYỆT"

      # ---- Bật hiện OTP để test ngay --------------------------------------
      AppSetting.set_flag(AppSetting::SHOW_OTP_KEY, true)
      puts "   ✓ Đã BẬT hiện mã OTP trên màn hình (tắt tại /admin/settings)"

      puts "\n✅ Xong: #{Workspace.count} workspace · #{User.count} tài khoản nhân sự · #{Member.count} khách."
    end
  end
end
