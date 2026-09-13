module Pwa
  # Per-shop app icon, drawn from the shop's initials on its own brand colour.
  #
  # This is a white-label product, yet every shop without an uploaded logo was
  # falling back to /icon.png — the PLATFORM's sparkle. Their customers saw
  # Dynamic Loyalty on the login screen, in the browser tab, and as the icon on
  # their home screen after installing the shop's app. At the time of writing
  # that was every shop in production.
  class IconsController < ApplicationController
    include TenantResolver
    skip_before_action :set_locale, raise: false

    SIZES = [96, 180, 192, 512].freeze

    def show
      ws = resolve_workspace
      # An uploaded logo always wins; this endpoint is only the fallback.
      return redirect_to(rails_storage_proxy_path(ws.logo, only_path: true)) if ws&.logo&.attached?

      svg = icon_svg(ws)
      # The icon only changes when the shop renames or re-themes, both of which
      # bump updated_at, so it can be cached hard.
      fresh_when(etag: [ws&.id, ws&.updated_at, params[:format], params[:size]], public: true)
      return if performed?

      expires_in 7.days, public: true
      case params[:format]
      when "png" then send_png(svg)
      else render plain: svg, content_type: "image/svg+xml"
      end
    end

    private

    def size
      s = params[:size].to_i
      SIZES.include?(s) ? s : 512
    end

    def send_png(svg)
      png = rasterize(svg)
      return redirect_to("/icon.png") if png.nil?
      send_data png, type: "image/png", disposition: "inline"
    end

    # ImageMagick is present on the server, but a missing SVG delegate must never
    # break an app install — fall back to the static icon instead of 500ing.
    def rasterize(svg)
      require "mini_magick"
      Tempfile.create(["icon", ".svg"]) do |f|
        f.write(svg)
        f.flush
        img = MiniMagick::Image.open(f.path)
        img.format("png")
        img.resize("#{size}x#{size}")
        return File.binread(img.path)
      end
    rescue StandardError => e
      Rails.logger.warn("[Icon] rasterize failed: #{e.class} #{e.message}")
      nil
    end

    def icon_svg(ws)
      initials = ws&.logo_initials.presence || "DL"
      primary  = ws&.theme_value("primary") || Workspace::DEFAULT_THEME["primary"]
      ink      = ws&.theme_value("on_primary") || Workspace::DEFAULT_THEME["on_primary"]
      # Two sizes of text so one long initial pair still fits the tile.
      font = initials.length > 1 ? 230 : 280
      <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="#{ERB::Util.h(ws&.name)}">
          <defs>
            <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#{ERB::Util.h(primary)}"/>
              <stop offset="1" stop-color="#{ERB::Util.h(darken(primary))}"/>
            </linearGradient>
          </defs>
          <rect width="512" height="512" rx="112" fill="url(#g)"/>
          <text x="256" y="256" fill="#{ERB::Util.h(ink)}" font-size="#{font}" font-weight="700"
                font-family="Helvetica, Arial, sans-serif" text-anchor="middle" dominant-baseline="central">#{ERB::Util.h(initials)}</text>
        </svg>
      SVG
    end

    # Rough shade for the gradient's far stop; falls back to the colour itself
    # for any value that is not a plain 6-digit hex.
    def darken(hex, factor = 0.62)
      m = hex.to_s.strip.match(/\A#?(\h{2})(\h{2})(\h{2})\z/)
      return hex unless m
      format("#%02X%02X%02X", *m.captures.map { |c| (c.to_i(16) * factor).round.clamp(0, 255) })
    end
  end
end
