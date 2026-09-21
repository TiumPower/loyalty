module Merchant
  class CampaignsController < BaseController
    before_action :require_manager!, except: [:index, :show, :banner_jobs]
    before_action :set_campaign, only: [:show, :edit, :update, :qr, :pause, :resume, :destroy, :generate_banner, :push]

    def index
      return render_locked_feature(:campaigns) if feature_locked?(:campaigns)
      @campaigns = current_workspace.campaigns.recent.includes(:reward).to_a
    end

    def new
      # A fresh campaign is NOT live: the merchant reviews it and presses
      # "Bắt đầu chạy" on the campaign page when it should go out.
      @campaign = current_workspace.campaigns.new(campaign_type: "promo_voucher", audience: "all",
                                                  status: "draft", starts_at: Time.current)
      @rewards = current_workspace.rewards.active.ordered.to_a
    end

    def create
      unless current_workspace.plan_allows?(:campaigns)
        plan = Plan.lowest_allowing(:campaigns)
        msg = plan ? "Chiến dịch có ở gói #{plan.name} trở lên. Vui lòng nâng cấp gói." \
                   : "Chiến dịch hiện chưa được bật ở gói nào."
        return redirect_to merchant_campaigns_path, alert: msg
      end
      @campaign = current_workspace.campaigns.new(campaign_params)
      if @campaign.save
        maybe_generate_promo! # first: the banner composites this promo's real QR
        banner = maybe_generate_banner!
        notice = t("merchant.campaigns.created_draft", name: @campaign.name)
        notice += " " + t("merchant.campaigns.created_banner_suffix") if banner
        redirect_to merchant_campaign_path(@campaign), notice: notice
      else
        @rewards = current_workspace.rewards.active.ordered.to_a
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @promo = @campaign.promo_codes.first
      @promo_url = helpers.customer_scan_url(current_workspace, promo: @promo.token) if @promo
      @share_url = public_campaign_url(@campaign.share_token!)
      @counts = MemberSegments.counts if current_membership&.can_manage?
      # Nothing on this page showed that the campaign had already been pushed,
      # so a manager could notify every customer a second time without knowing.
      @sends = @campaign.broadcasts.where.not(sent_at: nil).order(sent_at: :desc).limit(5).to_a
    end

    def edit
      @rewards = current_workspace.rewards.active.ordered.to_a
    end

    def update
      if @campaign.update(campaign_params)
        redirect_to merchant_campaign_path(@campaign), notice: "Đã cập nhật chiến dịch."
      else
        @rewards = current_workspace.rewards.active.ordered.to_a
        render :edit, status: :unprocessable_entity
      end
    end

    # AI content suggestion (title + body) for the campaign draft. Returns JSON;
    # the form fills the fields client-side. No campaign is persisted here.
    def generate_content
      data = ClaudeService.safe_call(fallback: {}) do
        ClaudeService.new(model: ClaudeService::OPUS, max_tokens: 1200)
                     .json(content_prompt)
      end
      if data.present? && (data["title"].present? || data["body"].present?)
        render json: { ok: true, title: data["title"].to_s, body: data["body"].to_s }
      else
        render json: { ok: false, error: ClaudeService.configured? ? "ai_failed" : "not_configured" },
               status: :service_unavailable
      end
    end

    # Kick off (async) AI banner generation via OpenAI Images.
    def generate_banner
      unless AiImageService.configured?
        return redirect_to merchant_campaign_path(@campaign), alert: t("merchant.campaigns.banner_no_key")
      end
      queue_banner!(params[:include_qr] == "1" && @campaign.promo_codes.exists?)
      redirect_to merchant_campaign_path(@campaign), notice: t("merchant.campaigns.banner_generating")
    end

    # JSON poll for the global progress bar: banner jobs started recently.
    def banner_jobs
      cutoff = 10.minutes.ago
      jobs = current_workspace.campaigns
               .where(banner_status: %w[generating ready failed])
               .where("banner_requested_at > ?", cutoff)
               .order(banner_requested_at: :desc).limit(10)
               .map do |c|
        { id: c.id, name: c.name, status: c.banner_status,
          elapsed: (Time.current - (c.banner_requested_at || Time.current)).to_i,
          requested_at: c.banner_requested_at&.to_i,
          url: merchant_campaign_path(c) }
      end
      render json: { jobs: jobs }
    end

    # Push the campaign announcement to one or more customer groups (logged as a
    # Broadcast). The merchant picks the groups in the multi-select; recipients are
    # the de-duplicated union across every selected group.
    def push
      keys = Array(params[:segments]).map(&:to_s).select { |k| MemberSegments::PRESETS.key?(k) }.uniq
      keys = [@campaign.audience] if keys.empty? # fall back to the campaign's own audience
      members = keys.flat_map { |k| MemberSegments.resolve(k).to_a }.uniq(&:id)

      if members.empty?
        return redirect_to merchant_campaign_path(@campaign),
                           alert: t("merchant.campaigns.push_empty")
      end

      label = keys.map { |k| MemberSegments.label(k) }.join(", ")
      broadcast = current_workspace.broadcasts.create!(
        campaign: @campaign, segment_key: (keys.one? ? keys.first : "all"),
        audience_label: label, title: (@campaign.content_value("title").presence || @campaign.name),
        body: @campaign.content_value("body").to_s, created_by: current_user
      )
      broadcast.deliver!(members)
      redirect_to merchant_campaign_path(@campaign),
                  notice: t("merchant.campaigns.push_sent", n: members.size)
    end

    # Downloadable promo QR (SVG) for printing on posters / receipts.
    def qr
      promo = @campaign.promo_codes.first
      raise ActiveRecord::RecordNotFound unless promo
      url = helpers.customer_scan_url(current_workspace, promo: promo.token)
      png = helpers.qr_png(url, color: "1A1A1A", size: 720)
      send_data png, type: "image/png", filename: "promo-#{promo.token}.png", disposition: "attachment"
    end

    # Pause: stops the campaign and disables its promo QR (khách hết quét nhận được).
    def pause
      @campaign.update(status: "paused")
      @campaign.promo_codes.update_all(active: false)
      redirect_to merchant_campaign_path(@campaign), notice: "Đã tạm dừng chiến dịch."
    end

    # Also the "start" action for a draft/scheduled campaign that has never run.
    def resume
      was_draft = %w[draft scheduled].include?(@campaign.status)
      @campaign.update(status: "running")
      @campaign.promo_codes.update_all(active: true)
      redirect_to merchant_campaign_path(@campaign),
                  notice: was_draft ? "Đã bắt đầu chạy chiến dịch." : "Đã tiếp tục chiến dịch."
    end

    # Xoá cả chiến dịch + mã QR/lượt nhận của nó (voucher đã phát cho khách giữ nguyên).
    def destroy
      @campaign.destroy
      redirect_to merchant_campaigns_path, notice: "Đã xoá chiến dịch."
    end

    private

    def nav_key = :campaigns

    def set_campaign
      @campaign = current_workspace.campaigns.find(params[:id])
    end

    def campaign_params
      params.require(:campaign).permit(:name, :campaign_type, :audience, :reward_id,
                                       :starts_at, :ends_at, :status,
                                       content: [:title, :body, :tone])
    end

    # Prompt for the AI content generator, built from the in-progress form.
    def content_prompt
      ctype    = params[:campaign_type].to_s.presence_in(Campaign::TYPES) || "promo_voucher"
      audience = params[:audience].to_s.presence_in(Campaign::AUDIENCES) || "all"
      reward   = params[:reward_id].present? ? current_workspace.rewards.find_by(id: params[:reward_id]) : nil
      tone     = current_workspace.branding_value("tone")
      # The campaign name is the merchant's own description of the campaign, so it
      # carries more intent than the type/audience dropdowns; feed it to the model.
      cname    = params[:name].to_s.strip.delete("\n").first(120)
      <<~PROMPT
        Viết nội dung một chiến dịch marketing cho cửa hàng "#{current_workspace.name}".
        #{cname.present? ? "Tên chiến dịch (chủ đề, phải dựa vào đây): #{cname}." : ''}
        Loại chiến dịch: #{I18n.t("merchant.campaign_types.#{ctype}", default: ctype)}.
        Nhóm khách nhắm tới: #{I18n.t("merchant.campaign_audiences.#{audience}", default: audience)}.
        #{reward ? "Ưu đãi kèm theo: #{reward.title} (#{reward.value_label})." : ''}
        Giọng điệu: #{tone}. Viết tiếng Việt, hấp dẫn, NGẮN GỌN, phù hợp gửi cho khách qua app.
        Bắt buộc: title tối đa 60 ký tự; body tối đa 180 ký tự, 1-2 câu. Không dùng markdown.
        Chỉ trả về đúng một object JSON: {"title": "...", "body": "..."}.
      PROMPT
    end

    # AI banner straight from the create form (the campaign page has its own
    # button for later). Returns true when a job was queued.
    def maybe_generate_banner!
      return false unless params[:generate_banner] == "1" && AiImageService.configured?
      # Only promise a QR on the banner when there is actually a code to put
      # there — the merchant may have skipped the claim QR above.
      with_qr = params[:banner_include_qr] == "1" && @campaign.promo_codes.exists?
      queue_banner!(with_qr)
      true
    end

    def queue_banner!(with_qr)
      @campaign.update_columns(banner_status: "generating", banner_requested_at: Time.current,
                               updated_at: Time.current)
      GenerateCampaignBannerJob.perform_later(@campaign.id, with_qr)
    end

    def maybe_generate_promo!
      return unless params[:generate_qr] == "1" && @campaign.reward_id.present?
      current_workspace.promo_codes.create!(
        campaign: @campaign, reward: @campaign.reward,
        max_claims: params[:max_claims].presence&.to_i,
        starts_at: @campaign.starts_at, ends_at: @campaign.ends_at,
        # Draft campaign → the QR stays dead until the merchant starts it.
        active: @campaign.status == "running"
      )
    end
  end
end
