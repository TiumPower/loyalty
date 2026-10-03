module ApplicationHelper
  # Brand logos (simple-icons paths) for social-share mission networks, so tasks
  # show the real Facebook/Instagram/TikTok/Zalo mark instead of an emoji.
  SOCIAL_LOGOS = {
    "facebook"  => { color: "#1877F2", path: "M9.101 23.691v-7.98H6.627v-3.667h2.474v-1.58c0-4.085 1.848-5.978 5.858-5.978.401 0 .955.042 1.468.103a8.68 8.68 0 0 1 1.141.195v3.325a8.623 8.623 0 0 0-.653-.036 26.805 26.805 0 0 0-.733-.009c-.707 0-1.259.096-1.675.309a1.686 1.686 0 0 0-.679.622c-.258.42-.374.995-.374 1.752v1.297h3.919l-.386 2.103-.287 1.564h-3.246v8.245C19.396 23.238 24 18.179 24 12.044c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.628 3.874 10.35 9.101 11.647Z" },
    "instagram" => { color: "#E4405F", path: "M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zM12 0C8.741 0 8.333.014 7.053.072 2.695.272.273 2.69.073 7.052.014 8.333 0 8.741 0 12c0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98C8.333 23.986 8.741 24 12 24c3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98C15.668.014 15.259 0 12 0zm0 5.838a6.162 6.162 0 1 0 0 12.324 6.162 6.162 0 0 0 0-12.324zM12 16a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm6.406-11.845a1.44 1.44 0 1 0 0 2.881 1.44 1.44 0 0 0 0-2.881z" },
    "tiktok"    => { color: "#111111", path: "M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.08-.14 1.62.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z" },
    # Zalo has no icon-font glyph — use the official logo asset (app/assets/images/zalo.png).
    "zalo"      => { asset: "zalo.png" }
  }.freeze

  # Brand-logo mark for a social network (nil for unknown). Most are inline SVG;
  # Zalo uses its official image asset.
  def social_logo(platform, size: 22)
    data = SOCIAL_LOGOS[platform.to_s]
    return nil unless data
    if data[:asset]
      return image_tag(data[:asset], width: size, height: size, alt: "Zalo",
                       style: "display:inline-block; vertical-align:middle; flex:none; object-fit:contain;")
    end
    inner = data[:body] || %(<path d="#{data[:path]}" fill="#{data[:color]}"/>)
    raw %(<svg viewBox="0 0 24 24" width="#{size}" height="#{size}" aria-hidden="true" style="display:inline-block; vertical-align:middle; flex:none;">#{inner}</svg>)
  end

  # Icon for a mission: the real brand logo for a per-network social_share task,
  # otherwise the mission's emoji.
  def mission_icon(mission, size: 22)
    if mission.respond_to?(:platform) && (logo = social_logo(mission.platform, size: size))
      logo
    else
      raw %(<span style="font-size:#{size}px; line-height:1;">#{ERB::Util.html_escape(mission.display_icon)}</span>)
    end
  end

  # Workspace resolved purely from the request host — safe to call from Devise
  # controllers (login / password reset) where no tenant is set. Display-only.
  def host_workspace
    return @host_workspace if defined?(@host_workspace)
    sub = request.subdomains.first
    ws  = Workspace.find_by(subdomain: sub) if sub.present? &&
          !TenantResolver::RESERVED_SUBDOMAINS.include?(sub)
    @host_workspace = ws || Workspace.find_by(custom_domain: request.host)
  rescue StandardError
    @host_workspace = nil
  end
  # Icon/favicon URL for a workspace: the uploaded logo when present, else the
  # platform default. Root-relative so it works on any shop host.
  def workspace_icon_url(ws, **opts)
    if ws&.logo&.attached?
      # Proxy (not redirect): a stable, cacheable URL that streams the bytes
      # through the app. The redirect variant hands back a short-lived signed
      # disk URL that expires (~5 min) — once the browser/PWA caches that 302,
      # the favicon/logo later 404s and shows a broken "?" image.
      rails_storage_proxy_path(ws.logo, only_path: true)
    elsif ws
      # A white-label app must never show the PLATFORM's logo to a shop's own
      # customers. With no upload, draw the shop's initials on its brand colour.
      pwa_icon_path(workspace_slug: ws.slug, format: opts[:format] || "svg",
                    size: opts[:size], only_path: true)
    else
      "/icon.png"
    end
  end

  # Workspace avatar: the uploaded logo (cover-cropped, inherits the box shape)
  # if present, otherwise the initials. Pass extra style for the box.
  def workspace_avatar(ws, klass: "avatar", style: nil)
    # Uploaded logo if present, otherwise the shop's initials on its brand
    # colour — rendered inline rather than fetched, since the markup is cheaper
    # than a request and picks up the live theme variables.
    inner = if ws&.logo&.attached?
      image_tag(workspace_icon_url(ws), alt: "", style: "width:100%;height:100%;object-fit:cover;")
    else
      content_tag(:span, ws&.logo_initials,
                  style: "display:grid;place-items:center;width:100%;height:100%;" \
                         "background:linear-gradient(150deg,var(--primary),color-mix(in srgb,var(--primary) 58%,#000));" \
                         "color:var(--on-primary,#fff);font-weight:700;letter-spacing:.02em;")
    end
    content_tag(:div, inner, class: klass, style: ["overflow:hidden", style].compact.join(";"))
  end

  # Just the given name, for the home greeting: "Chào buổi chiều, Tô Trung Tuân"
  # wraps onto two lines and pushes the bell out of the header, and a greeting
  # reads better on a first name anyway. Vietnamese names put it last.
  # Lời chào theo buổi trong ngày. Dùng giờ của múi giờ app (Asia/Ho_Chi_Minh
  # trên production) chứ không phải giờ máy chủ.
  def greeting_for(member)
    part = case Time.current.hour
           when 5..11  then "morning"
           when 12..17 then "afternoon"
           else "evening"
           end
    # Khách đăng nhập bằng SĐT chưa khai tên thì `display_name` rơi về "Thành
    # viên", và `greeting_name` cắt lấy từ cuối — ra "Chào buổi tối, viên!".
    # Chưa có tên thì chào trống, đừng chào một mảnh chữ.
    name = member.name.presence && greeting_name(member)
    name.present? ? t("customer.home.greeting_#{part}", name: name)
                  : t("customer.home.greeting_#{part}_anon")
  end

  def greeting_name(member)
    full = member.display_name.to_s.strip
    parts = full.split(/\s+/)
    parts.size > 1 && I18n.locale.to_s == "vi" ? parts.last : parts.first.to_s
  end

  # One line saying what a mission actually asks for. Missions carry no
  # description column, and the design wants a sentence under the title — so
  # build it from the mission's own type and goal rather than leaving a gap.
  def mission_goal_text(mission, shop: nil)
    shop ||= mission.workspace&.name
    n = mission.goal.to_i
    case mission.mission_type
    when "spend" then t("customer.missions.goal_spend", amount: number_with_delimiter(n), shop: shop)
    else t("customer.missions.goal_#{mission.mission_type}", n: n, shop: shop, default: "")
    end
  end

  # "3 orders left" — what is still outstanding on a mission, which is what the
  # design's compact home card leads with (the full goal lives on the missions
  # screen).
  def mission_left_text(mission, progress)
    return t("customer.missions.completed") if progress.completed?
    left = [mission.goal.to_i - progress.progress.to_i, 0].max
    case mission.mission_type
    when "spend" then t("customer.missions.left_spend", amount: number_with_delimiter(left))
    else t("customer.missions.left_#{mission.mission_type}", n: left, default: t("customer.missions.left_generic", n: left))
    end
  end

  # Which half of the day the customer is opening the app in — the home screen
  # greets them with it. Uses the app time zone, not the browser's.
  def greeting_period
    h = Time.current.hour
    return "morning"   if h < 11
    return "afternoon" if h < 18
    "evening"
  end

  # The shop's wide photo, for the home card and the shop page. Falls back to
  # the logo on its brand tint so the frame is never an empty grey box.
  def shop_cover(ws, size: 780)
    if ws&.cover&.attached?
      image_tag(ws.cover.variant(resize_to_fill: [size, (size * 0.56).round]), alt: "",
                style: "width:100%;height:100%;object-fit:cover;display:block;")
    elsif ws&.logo&.attached?
      image_tag(workspace_icon_url(ws), alt: "",
                style: "width:56%;height:56%;object-fit:contain;display:block;margin:auto;")
    else
      content_tag(:span, ws&.logo_initials,
                  style: "font-size:34px;font-weight:700;color:var(--primary);opacity:.5;")
    end
  end

  # Reward artwork. The design leads with a photo wherever a reward appears, but
  # a shop that has not uploaded one still needs something in the frame — so
  # fall back to the reward's emoji on a brand tint. `size` drives the variant
  # only; the box itself is sized by the surrounding component's CSS.
  # `ratio` là tỉ lệ của KHUNG sẽ chứa ảnh (rộng ÷ cao).
  #
  # Trước đây mọi biến thể đều cắt vuông rồi thả vào khung 4:3 hay 16:10, và
  # `object-fit: cover` cắt thêm lần nữa — hai lần cắt chồng nhau, nên chủ thể
  # của ảnh trôi ra ngoài khuôn hình. Cắt đúng một lần, đúng tỉ lệ sẽ dùng.
  def reward_art(reward, size: 320, emoji_size: nil, ratio: 1)
    if reward&.image&.attached?
      height = (size / ratio.to_f).round
      image_tag(reward.image.variant(resize_to_fill: [size, height]), alt: "",
                style: "width:100%;height:100%;object-fit:cover;display:block;")
    else
      reward_placeholder(reward, emoji_size: emoji_size)
    end
  end

  # Khi quán chưa tải ảnh cho ưu đãi.
  #
  # Trước đây chỗ này chỉ là một emoji đặt giữa ô trống — nhìn như ảnh chưa
  # tải xong, và nằm cạnh những ưu đãi CÓ ảnh thì trông như lỗi. Giờ nó là một
  # tấm nền có bố cục: dải chuyển màu theo màu thương hiệu của quán cộng hai
  # vòng tròn mờ, lấp đầy đúng khung ảnh, nên hàng thẻ vẫn đều nhau.
  #
  # Vẽ bằng CSS theo biến màu của quán chứ không dùng một tệp ảnh có sẵn: một
  # tấm ảnh tĩnh sẽ chọi với bảng màu của mọi quán khác, và ảnh stock thì kéo
  # theo giấy phép của bên thứ ba vào một sản phẩm đem bán.
  def reward_placeholder(reward, emoji_size: nil)
    content_tag(:span, class: "l-artfallback") do
      content_tag(:span, reward&.display_icon, class: "em",
                  style: ("font-size:#{emoji_size}px" if emoji_size))
    end
  end

  # Member avatar: uploaded image (cover-cropped) if present, else initials.
  def member_avatar(member, klass: "avatar", style: nil)
    if member&.avatar&.attached?
      content_tag(:div, image_tag(rails_storage_proxy_path(member.avatar, only_path: true), style: "width:100%;height:100%;object-fit:cover;"),
                  class: klass, style: ["overflow:hidden", style].compact.join(";"))
    else
      content_tag(:div, member&.initials, class: klass, style: style)
    end
  end

  # Builds the customer-app scan-resolve URL for a workspace (what promo / POS
  # QR codes encode). Dev uses the /w/:slug path form on the current host; a
  # custom domain / subdomain is used when configured.
  def customer_scan_url(workspace, query = {})
    host = if workspace.custom_domain.present?
      "#{request.protocol}#{workspace.custom_domain}"
    else
      "#{request.protocol}#{request.host_with_port}/w/#{workspace.slug}"
    end
    "#{host}/scan/resolve?#{query.to_query}"
  end

  # Referral join link a member shares (opens the shop app + stashes the code).
  def customer_join_url(workspace, code)
    host = if workspace.custom_domain.present?
      "#{request.protocol}#{workspace.custom_domain}"
    else
      "#{request.protocol}#{request.host_with_port}/w/#{workspace.slug}"
    end
    "#{host}/join/#{code}"
  end

  # Sensible default perks per tier when a workspace hasn't customised benefits.
  def default_benefits(tier)
    perks = ["Tích ×#{tier.multiplier} điểm mỗi hoá đơn"]
    perks << "Ưu đãi độc quyền theo hạng" if tier.multiplier.to_f > 1
    perks << "Quà sinh nhật đặc biệt"      if tier.multiplier.to_f >= 1.5
    perks << "Ưu tiên hỗ trợ & sự kiện VIP" if tier.multiplier.to_f >= 2
    perks
  end

  # The tier screen lists benefits as a label with its value on the right, so a
  # member can read what the tier is worth at a glance. A shop that wrote its
  # own benefit lines gets those as plain rows (no value to show).
  def tier_benefit_rows(tier)
    return tier.benefits.map { |b| [:sparkles, b, nil] } if tier.benefits.present?
    m = tier.multiplier.to_f
    rows = [[:flame, t("customer.tiers.multiplier"), "#{tier.multiplier}x"]]
    rows << [:gift,    t("customer.tiers.b_birthday"), t("customer.tiers.b_yes")] if m >= 1.5
    rows << [:mail,    t("customer.tiers.b_support"),  t("customer.tiers.b_yes")] if m >= 2
    rows << [:sparkles, t("customer.tiers.b_events"),  t("customer.tiers.b_invited")] if m > 1
    rows
  end

  # One glyph per membership tier. The design draws the gold tier as a star in a
  # hexagon crest; the others follow the same idea so a badge is recognisable
  # before you read it. Tiers are merchant-editable — they can be renamed, added
  # to, or given their own keys — so an unknown key falls back to its rung on
  # the ladder rather than to nothing.
  # Hạng → huy hiệu. Khoá là chính nó khi gặp bốn hạng quen thuộc; workspace
  # tự đặt tên hạng khác thì rơi về nấc thang theo `position`.
  TIER_RUNGS = %i[bronze silver gold diamond].freeze

  def tier_icon(tier)
    return :bronze if tier.nil?
    key = tier.key.to_s.to_sym
    return key if IconsHelper::TIER_BADGES.key?(key)
    TIER_RUNGS[tier.position.to_i] || :bronze
  end

  # Huy hiệu hạng ở cỡ bất kỳ, màu lấy từ `color` của thẻ bao ngoài.
  def tier_glyph(tier, size: 16)
    tier_badge(tier_icon(tier), size: size)
  end

  # The tier badge as the design draws it: a soft tinted pill with the tier's
  # own solid glyph and lettering.
  def tier_pill(tier, size: nil, klass: "l-pill tier")
    return "".html_safe if tier.nil?
    style = +"background:#{tier.pill_background}; color:#{tier.pill_foreground};"
    style << " box-shadow: inset 0 0 0 1.5px #{tier.pill_ring};" if tier.pill_ring
    content_tag(:span, class: klass, style: style) do
      safe_join([tier_glyph(tier, size: size || 13), tier.name])
    end
  end

  # Whether a branch is open right now, or nil when it has never said. Hours
  # live on the outlet (a chain's branches keep different ones); a branch that
  # has not filled them in gets no badge rather than a cheerful guess.
  # "Quán · Chi nhánh" — nhưng chỉ khi chi nhánh thật sự nói thêm điều gì.
  #
  # Rất nhiều quán một cơ sở đặt tên chi nhánh trùng luôn tên quán, nên nối vô
  # điều kiện sẽ ra "Highland · Highland". Màn hình POS đã tự né bẫy này theo
  # cách riêng của nó; giờ cả ba màn hình cộng điểm dùng chung một luật.
  def shop_and_outlet(outlet, workspace: current_workspace)
    shop = workspace&.name.to_s.strip
    name = outlet&.name.to_s.strip
    return shop if name.blank?
    return name if shop.blank?

    a = squash_name(name)
    b = squash_name(shop)
    return shop if a == b
    # "Highland Lê Lợi" đã mang sẵn tên quán — tên chi nhánh tự nó là đủ.
    return name if a.include?(b)
    "#{shop} · #{name}"
  end

  # So tên bỏ qua hoa thường, dấu và khoảng trắng thừa.
  def squash_name(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def shop_open_state(outlet)
    return nil unless outlet.respond_to?(:hours?) && outlet.hours?
    open = outlet.open_at?
    { open: open,
      label: open ? t("customer.home.open_until", time: outlet.closes_at)
                  : t("customer.home.closed_until", time: outlet.opens_at) }
  end

  # Which build the customer is looking at. Capistrano names each release after
  # its timestamp, so the directory is the only version number this app has —
  # and it is the one thing worth having when a customer reports something odd.
  def app_build_label
    @app_build_label ||= begin
      dir = Rails.root.basename.to_s
      dir.match?(/\A\d{14}\z/) ? "v#{dir[0, 8]}.#{dir[8, 4]}" : "dev"
    end
  end

  # Icon per amenity. Keys are Workspace::AMENITIES; anything unknown gets a
  # tick, which still reads as "yes, this place has that".
  AMENITY_ICONS = {
    "wifi" => :globe, "power_outlets" => :flame, "takeaway" => :store,
    "indoor_seating" => :home, "outdoor_seating" => :pin, "card_payment" => :wallet_cards,
    "parking" => :navigate, "air_con" => :sparkles, "pet_friendly" => :star,
    "kid_friendly" => :users
  }.freeze
  def amenity_icon(key) = AMENITY_ICONS.fetch(key.to_s, :check)

  # A collected stamp, drawn as a rubber-stamp impression: two rings, a
  # four-point spark and the stamp's number. The roughened edge comes from an
  # SVG turbulence filter defined once per page (see `stamp_ink_filter`); a
  # browser that cannot resolve it simply draws clean rings, which still reads
  # as a stamp.
  #
  # Each one is tilted a few degrees so a full card looks hand-stamped rather
  # than printed — deterministic from the index, so it does not jump about on
  # re-render.
  SPARK = "M24 11.6c1.2 7.1 5.3 11.2 12.4 12.4-7.1 1.2-11.2 5.3-12.4 12.4" \
          "-1.2-7.1-5.3-11.2-12.4-12.4 7.1-1.2 11.2-5.3 12.4-12.4Z"

  def stamp_mark(number)
    tilt = (number.to_i * 37 % 9) - 4
    body = <<~SVG
      <svg viewBox="0 0 48 48" class="l-stampmark" style="rotate:#{tilt}deg;" aria-hidden="true">
        <g filter="url(#l-ink)">
          <circle cx="24" cy="24" r="20.4" fill="none" stroke="currentColor" stroke-width="2.4"/>
          <circle cx="24" cy="24" r="16.4" fill="none" stroke="currentColor" stroke-width="1.4"
                  stroke-dasharray="0.5 3" stroke-linecap="round"/>
          <path d="#{SPARK}" fill="currentColor"/>
        </g>
        <text x="33" y="35.5" text-anchor="middle" font-size="9.5" font-weight="700"
              fill="currentColor" font-family="inherit">#{number}</text>
      </svg>
    SVG
    body.html_safe
  end

  # The one-per-page definition the marks above reference. Rendering it more
  # than once would repeat the id.
  def stamp_ink_filter
    <<~SVG.html_safe
      <svg width="0" height="0" style="position:absolute;" aria-hidden="true">
        <filter id="l-ink" x="-20%" y="-20%" width="140%" height="140%">
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" seed="7" result="n"/>
          <feDisplacementMap in="SourceGraphic" in2="n" scale="1.6" xChannelSelector="R" yChannelSelector="G"/>
        </filter>
      </svg>
    SVG
  end
end
