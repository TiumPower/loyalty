module Merchant
  class AppearancesController < BaseController
    before_action :require_manager!, only: [:update, :suggest_theme]

    # Built-in theme presets demonstrating dynamic branding on one layout.
    PRESETS = {
      "cozy_cafe" => {
        "label" => "Cozy Cafe",
        "theme" => { "primary" => "#8C4A2F", "primary_2" => "#E08A3C", "on_primary" => "#FFF7EE",
                     "surface" => "#FBF6EF", "surface_2" => "#F3E9DD", "ink" => "#3A2A20",
                     "ink_2" => "#7A6656", "line" => "#E7D9C9", "radius" => "22px",
                     "font_display" => "Fraunces", "font_body" => "Plus Jakarta Sans" }
      },
      "modern_beauty" => {
        "label" => "Modern Beauty",
        "theme" => { "primary" => "#C64B8C", "primary_2" => "#9B6DD6", "on_primary" => "#FFF5FB",
                     "surface" => "#FBF3F8", "surface_2" => "#F3E6F1", "ink" => "#3A2634",
                     "ink_2" => "#7C6376", "line" => "#EBD7E6", "radius" => "26px",
                     "font_display" => "Playfair Display", "font_body" => "Plus Jakarta Sans" }
      },
      "retail_bold" => {
        "label" => "Retail Bold",
        "theme" => { "primary" => "#111111", "primary_2" => "#E0B54A", "on_primary" => "#FFFDF5",
                     "surface" => "#FAFAF7", "surface_2" => "#EFEDE6", "ink" => "#1A1A1A",
                     "ink_2" => "#6B6B66", "line" => "#E2E0D8", "radius" => "14px",
                     "font_display" => "Fraunces", "font_body" => "Inter" }
      }
    }.freeze

    def show
      @workspace = current_workspace
      @presets   = PRESETS
    end

    def update
      @workspace = current_workspace
      if params[:preset].present? && PRESETS.key?(params[:preset])
        @workspace.theme = PRESETS[params[:preset]]["theme"]
      else
        # theme_value falls back to the default for anything that is not a
        # colour, so a bad value would silently revert. Say so instead.
        colors = theme_params.to_h
        bad = colors.slice(*Workspace::THEME_COLOR_KEYS)
                    .reject { |_, v| v.blank? || Workspace.hex_color?(v) }
        if bad.any?
          @workspace.errors.add(:base, "Màu không hợp lệ (#{bad.keys.join(", ")}) — dùng mã hex, VD #8C4A2F.")
          @presets = PRESETS
          return render :show, status: :unprocessable_entity
        end
        @workspace.theme    = (@workspace.theme || {}).merge(colors)
        @workspace.branding = (@workspace.branding || {}).merge(branding_params.to_h)
        # Check the upload BEFORE attaching. Attaching first and letting the
        # model validation fail leaves an unsaved blob on the record, and
        # re-rendering this page then raises "Cannot get a signed_id for a new
        # record" while trying to show it.
        if params[:logo].present?
          if (problem = logo_problem(params[:logo]))
            @workspace.errors.add(:logo, problem)
            @presets = PRESETS
            return render :show, status: :unprocessable_entity
          end
          @workspace.logo.attach(params[:logo])
        end
      end

      if @workspace.save
        redirect_to merchant_appearance_path, notice: "Đã cập nhật giao diện thương hiệu."
      else
        @presets = PRESETS
        render :show, status: :unprocessable_entity
      end
    end

    # AI palette suggestion derived from the shop's logo. Returns JSON; the form
    # fills the colour pickers client-side. Nothing is saved until the merchant
    # clicks Save (the existing update path).
    def suggest_theme
      ws = current_workspace
      unless ws.logo.attached?
        return render json: { ok: false, error: "no_logo" }, status: :unprocessable_entity
      end

      palette = ClaudeService.safe_call(fallback: {}) do
        bytes = ws.logo.download
        media = ws.logo.content_type.presence || "image/png"
        ClaudeService.new(model: ClaudeService::OPUS, max_tokens: 400)
                     .vision_json(theme_prompt, image_bytes: bytes, media_type: media)
      end

      colors = sanitize_palette(palette)
      if colors.present?
        render json: { ok: true, theme: colors }
      else
        render json: { ok: false, error: ClaudeService.configured? ? "ai_failed" : "not_configured" },
               status: :service_unavailable
      end
    end

    private

    def nav_key = :appearance

    def theme_prompt
      <<~PROMPT
        Đây là logo của cửa hàng "#{current_workspace.name}". Hãy đề xuất bảng màu thương hiệu
        hài hoà, lấy cảm hứng từ màu chủ đạo của logo, cho một ứng dụng khách hàng thân thiết.
        Yêu cầu tương phản tốt: chữ đọc rõ trên nền.
        Trả về JSON đúng dạng, mỗi giá trị là mã hex (#RRGGBB):
        {"primary":"#...", "primary_2":"#...", "surface":"#...", "ink":"#..."}
        Trong đó: primary = màu thương hiệu chính (đậm), primary_2 = màu nhấn phụ,
        surface = màu nền sáng dịu, ink = màu chữ tối dễ đọc trên surface.
      PROMPT
    end

    HEX_RE = /\A#[0-9a-fA-F]{6}\z/
    def sanitize_palette(palette)
      return {} unless palette.is_a?(Hash)
      %w[primary primary_2 surface ink].each_with_object({}) do |k, out|
        v = palette[k].to_s.strip
        out[k] = v if v.match?(HEX_RE)
      end
    end

    # nil when the upload is fine, otherwise why it is not.
    def logo_problem(upload)
      return nil unless upload.respond_to?(:content_type)
      unless Workspace::LOGO_TYPES.include?(upload.content_type)
        return "phải là ảnh PNG, JPG, WEBP hoặc GIF"
      end
      size = upload.respond_to?(:size) ? upload.size : upload.tempfile.size
      if size.to_i > Workspace::LOGO_MAX_BYTES
        return "tối đa #{(Workspace::LOGO_MAX_BYTES / 1.megabyte).to_i}MB"
      end
      nil
    end

    def theme_params
      params.fetch(:theme, {}).permit(:primary, :primary_2, :on_primary, :surface, :surface_2,
                                      :ink, :ink_2, :line, :radius, :font_display, :font_body)
    end

    def branding_params
      params.fetch(:branding, {}).permit(:logo_text, :tagline, :customer_term, :tone)
    end
  end
end
