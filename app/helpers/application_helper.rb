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
end
