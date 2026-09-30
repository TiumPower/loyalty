namespace :loyalty do
  desc "Create one polished, fully-populated demo shop (F&B). ENV: SUBDOMAIN NAME EMAIL PASSWORD STATUS"
  task demo_shop: :environment do
    require "faker"
    Faker::Config.locale = "vi"

    # ENV strings come back as ASCII-8BIT; force UTF-8 so Vietnamese NAME can be
    # interpolated with UTF-8 literals without Encoding::CompatibilityError.
    utf8   = ->(v) { v.to_s.dup.force_encoding("UTF-8") }
    sub    = utf8.(ENV.fetch("SUBDOMAIN", "gaucafe"))
    name   = utf8.(ENV.fetch("NAME", "Gấu Coffee & Bakery"))
    email  = utf8.(ENV.fetch("EMAIL", "owner@#{sub}.vn")).downcase
    pass   = utf8.(ENV.fetch("PASSWORD", "loyalty1234"))
    status = utf8.(ENV.fetch("STATUS", "active"))

    ActsAsTenant.without_tenant do
      if Workspace.exists?(subdomain: sub)
        abort "❌ Subdomain '#{sub}' đã tồn tại. Xoá nó trước, hoặc chạy lại với SUBDOMAIN=<tên khác>."
      end
      Plan.seed_defaults!

      ws = Workspace.create!(
        name: name, subdomain: sub, slug: sub, industry: "fnb",
        status: status, plan: "growth", locale_default: "vi",
        paid_until: (status == "active" ? Time.current.end_of_month.end_of_day : nil),
        theme: Merchant::AppearancesController::PRESETS["cozy_cafe"]["theme"],
        branding: { "customer_term" => "bạn", "tagline" => "Ấm áp trong từng ly", "tone" => "friendly" },
        settings: { "onboarded" => true, "feedback_public" => true }
      )

      ActsAsTenant.with_tenant(ws) do
        WorkspaceBootstrap.call(ws)
        program = ws.loyalty_program
        program.update!(stamps_enabled: true, gamification_enabled: true, referral_enabled: true, referral_points: 100)

        # ---- Outlets (3 branches) -----------------------------------------
        outlets = [
          [ "MAIN", "Gấu Coffee — Thảo Điền", "12 Nguyễn Ư Dĩ, Thảo Điền, TP.Thủ Đức" ],
          [ "D1",   "Gấu Coffee — Quận 1",    "45 Lý Tự Trọng, Bến Nghé, Quận 1" ],
          [ "GV",   "Gấu Coffee — Gò Vấp",    "88 Quang Trung, Phường 10, Gò Vấp" ]
        ].map { |code, nm, addr| Outlet.create!(workspace: ws, code: code, name: nm, address: addr, active: true) }
        main = outlets.first

        # ---- Rewards catalog ----------------------------------------------
        rewards = [
          { title: "Cà phê sữa đá miễn phí",  kind: "voucher",  icon: "☕", cost_points: 300,  value: 0,     value_unit: "item" },
          { title: "Giảm 30% toàn menu trà",  kind: "discount", icon: "🧋", cost_points: 250,  value: 30,    value_unit: "percent" },
          { title: "Giảm 50.000đ hoá đơn",    kind: "voucher",  icon: "🎟️", cost_points: 800,  value: 50000, value_unit: "vnd" },
          { title: "Bánh ngọt tặng kèm",      kind: "gift",     icon: "🍰", cost_points: 500,  value: 0,     value_unit: "item", stock: 50 },
          { title: "Combo 2 ly + bánh",       kind: "voucher",  icon: "🥐", cost_points: 1200, value: 0,     value_unit: "item" },
          { title: "Quà sinh nhật đặc biệt",  kind: "gift",     icon: "🎂", cost_points: 0,    value: 0,     value_unit: "item", stock: 100 }
        ].each_with_index.map do |rw, i|
          Reward.create!(rw.merge(workspace: ws, active: true, position: i, valid_days: 30))
        end

        # ---- Gamification -------------------------------------------------
        gift = rewards.find { |r| r.title == "Bánh ngọt tặng kèm" }
        ws.stamp_cards.create!(title: "Mua 9 ly tặng 1", description: "Tích 1 tem mỗi ly, đủ 9 tem đổi 1 ly miễn phí",
                               icon: "🧋", target_count: 9, reward: gift, active: true)
        ws.missions.create!(title: "Check-in hôm nay",         icon: "📍", mission_type: "checkin", period: "daily",  goal: 1,      reward_points: 20, position: 0)
        ws.missions.create!(title: "Ghé 3 lần trong tuần",     icon: "🏪", mission_type: "visit",   period: "weekly", goal: 3,      reward_points: 50, position: 1)
        ws.missions.create!(title: "Chi tiêu 100.000đ hôm nay", icon: "💳", mission_type: "spend",   period: "daily",  goal: 100000, reward_points: 30, position: 2)
        [ [ "newbie", "Người mới", "Mua hàng lần đầu", "🌱", "first_purchase", 1 ],
         [ "regular", "Khách quen", "Mua đủ 10 lần", "☕", "purchases_count", 10 ],
         [ "collector", "Cao thủ điểm", "Tích luỹ 5.000 điểm", "💎", "points_total", 5000 ],
         [ "nightowl", "Cú đêm", "Mua sau 22h", "🦉", "night_owl", 1 ] ].each_with_index do |(k, n, d, ic, ct, th), i|
          ws.badges.create!(key: k, name: n, description: d, icon: ic, criteria_type: ct, threshold: th, position: i)
        end

        # ---- Campaigns (+ shared promo QR) --------------------------------
        free_coffee = rewards.first
        camp1 = ws.campaigns.create!(name: "Khai trương — tặng #{free_coffee.title}", campaign_type: "promo_voucher",
          audience: "all", status: "running", starts_at: Time.current, ends_at: 30.days.from_now,
          content: { "title" => "Quà khai trương 🎉", "body" => "Quét mã nhận ngay #{free_coffee.title} — không tốn điểm!" })
        ws.promo_codes.create!(campaign: camp1, reward: free_coffee, max_claims: 300,
                               starts_at: camp1.starts_at, ends_at: camp1.ends_at, active: true)
        ws.campaigns.create!(name: "Happy Hour cuối tuần", campaign_type: "double_points",
          audience: "all", status: "running", starts_at: Time.current, ends_at: 60.days.from_now,
          content: { "title" => "Nhân đôi điểm cuối tuần ⚡", "body" => "Mọi hoá đơn thứ 6–CN được x2 điểm." })
        ws.campaigns.create!(name: "Tri ân khách VIP", campaign_type: "promo_voucher",
          audience: "vip", status: "scheduled", starts_at: 7.days.from_now, ends_at: 37.days.from_now,
          content: { "title" => "Đặc quyền hạng Vàng/Kim Cương 👑", "body" => "Quà tặng riêng cho khách thân thiết." })

        # ---- Owner --------------------------------------------------------
        owner = User.find_or_initialize_by(email: email)
        owner.assign_attributes(name: "Chủ #{name}", title: "Chủ cửa hàng", locale: "vi",
                                password: pass, password_confirmation: pass) if owner.new_record?
        owner.save!
        Membership.find_or_create_by!(user: owner, workspace: ws) { |m| m.role = "owner"; m.outlet = main }

        # ---- Members with real ledgers (spread across tiers) --------------
        targets = [ 80, 320, 640, 1500, 2300, 3100, 4800, 5600, 7200, 9000, 12500, 16000 ]
        members = targets.each_with_index.map do |target, n|
          phone = "09#{format('%08d', ws.id * 1_000_000 + n)}"
          m = Member.create!(workspace: ws, phone: phone, name: Faker::Name.name,
                             birthday: Faker::Date.birthday(min_age: 18, max_age: 55),
                             email: (n.even? ? "khach#{n}@vidu.com" : nil))
          outlet = outlets.sample
          chunks = [ target / 3, target / 3, target - 2 * (target / 3) ].reject(&:zero?)
          chunks.each do |pts|
            amt = pts * program.earn_per_amount / program.earn_points
            at  = Faker::Time.between(from: 90.days.ago, to: 1.day.ago)
            pur = Purchase.create!(workspace: ws, member: m, outlet: outlet, amount: amt,
                                   points_earned: pts, source: "staff_scan", created_at: at, updated_at: at)
            PointTransaction.create!(workspace: ws, member: m, kind: "earn", amount: pts,
                                     source: pur, outlet: outlet, created_at: at, updated_at: at)
          end
          m.recompute_points!
          m
        end

        # ---- Wallet vouchers (some redeemed, some used) -------------------
        used_count = 0
        members.select { |m| m.points_balance >= 300 }.first(6).each_with_index do |m, i|
          reward = rewards.select { |r| r.cost_points.to_i.positive? && r.cost_points <= m.points_balance }.sample
          next unless reward
          res = RedeemReward.new(member: m, reward: reward).call
          if res.voucher && i.even?
            at = Faker::Time.between(from: 20.days.ago, to: 1.day.ago)
            res.voucher.update!(state: "used", used_at: at, used_outlet: main); used_count += 1
          end
        end

        # ---- Ratings (public feedback wall) -------------------------------
        reviews = [
          [ 5, "Cà phê ngon, không gian ấm cúng, nhân viên dễ thương!" ],
          [ 5, "Tích điểm đổi quà tiện lắm, tuần nào cũng ghé." ],
          [ 4, "Bánh ngọt ổn, chỗ ngồi hơi ít vào giờ cao điểm." ],
          [ 5, "Thẻ tem mua 9 tặng 1 quá đã 🧋" ],
          [ 4, "Wifi mạnh, phù hợp làm việc. Sẽ quay lại." ],
          [ 5, "Chương trình khai trương tặng cà phê free rất hời!" ]
        ]
        members.first(reviews.size).each_with_index do |m, i|
          st, cm = reviews[i]
          Rating.create!(workspace: ws, member: m, outlet: outlets.sample, stars: st, comment: cm,
                         created_at: Faker::Time.between(from: 40.days.ago, to: 1.day.ago))
        end

        # ---- Notifications + referral -------------------------------------
        m0 = members.first
        Notification.create!(workspace: ws, member: m0, kind: "promo", icon: "🎁",
                             title: "Ưu đãi cuối tuần cho bạn!", body: "Nhân đôi điểm cho mọi hoá đơn từ thứ 6 đến CN.")
        Notification.create!(workspace: ws, member: m0, kind: "reminder", icon: "⏰",
                             title: "Đã lâu chưa gặp lại!", body: "Ghé Gấu tuần này để nhận quà nhé.")
        members[1].update!(referred_by: members[0])
        Referral.create!(workspace: ws, referrer: members[0], referred: members[1],
                         state: "completed", reward_points: program.referral_points, completed_at: 3.days.ago)

        tiers = members.group_by(&:tier_key).transform_values(&:size)
        puts "✅ Đã tạo shop: #{name}"
        puts "   Subdomain : https://#{sub}.#{ApplicationController::PLATFORM_HOST}"
        puts "   Merchant  : #{email} / #{pass}"
        puts "   Chi nhánh : #{outlets.size} · Ưu đãi: #{rewards.size} · Chiến dịch: #{ws.campaigns.count}"
        puts "   Khách     : #{members.size} (hạng: #{tiers.inspect}) · Voucher đã dùng: #{used_count}"
        puts "   Đánh giá  : #{ws.ratings.count} · Nhiệm vụ: #{ws.missions.count} · Huy hiệu: #{ws.badges.count}"
      end
    end
  end
end
