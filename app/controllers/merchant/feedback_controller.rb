module Merchant
  class FeedbackController < BaseController
    before_action :require_manager!

    PER_PAGE = 50

    def show
      @count   = Rating.count
      @avg     = Rating.average(:stars)&.round(1) || 0
      @dist    = (1..5).to_h { |s| [s, Rating.where(stars: s).count] }
      @page    = [params[:page].to_i, 1].max
      @filter  = params[:filter].presence_in(%w[unanswered low]) # quick triage
      scope    = filtered(Rating.recent.includes(:member, :replied_by))
      @count_filtered = scope.count
      @ratings = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
      @has_more = @count_filtered > @page * PER_PAGE
      @rewards = assignable_rewards(current_workspace.automation(:low_rating)["reward_id"])
    end

    def update
      ws = current_workspace
      settings = ws.settings.merge(
        "feedback_public"   => params[:feedback_public] == "1",
        # Public review link (Google Maps / Facebook). Shown to happy customers
        # right after they rate the shop — the cheapest acquisition channel there is.
        "google_review_url" => normalized_review_url
      )
      # "Xin lỗi tự động": khách chấm thấp → tặng ngay một ưu đãi để giữ họ lại.
      # Một ưu đãi không dùng được sẽ khiến lời xin lỗi thành tay không.
      if (bad = first_unassignable(params[:low_rating_reward_id],
                                   keep: [current_workspace.automation(:low_rating)["reward_id"]]))
        return redirect_to merchant_feedback_path, alert: reward_unavailable_message(bad)
      end
      settings["automations"] = (settings["automations"] || {}).merge(
        "low_rating" => {
          "enabled"   => params[:low_rating_enabled] == "1",
          "reward_id" => params[:low_rating_reward_id].presence,
          "threshold" => params[:low_rating_threshold].to_i.clamp(1, 4)
        }
      )
      ws.update!(settings: settings)
      redirect_to merchant_feedback_path, notice: t("merchant.feedback.saved")
    end

    # Reply to one review. The reply is public on the shop page AND lands in the
    # customer's inbox — an unanswered complaint is a customer you've lost.
    def reply
      rating = Rating.find(params[:id])
      body   = params[:reply_body].to_s.strip

      if body.blank?
        rating.update!(reply_body: nil, replied_at: nil, replied_by_id: nil)
        return redirect_to merchant_feedback_path, notice: t("merchant.feedback.reply_removed")
      end

      rating.update!(reply_body: body, replied_at: Time.current, replied_by_id: current_user.id)
      notify_member(rating)
      redirect_to merchant_feedback_path, notice: t("merchant.feedback.reply_saved")
    end

    private

    def nav_key = :feedback

    def filtered(scope)
      case @filter
      when "unanswered" then scope.where(replied_at: nil)
      when "low"        then scope.where("stars <= 3")
      else scope
      end
    end

    # Accept a pasted link with or without a scheme; reject anything that isn't
    # an http(s) URL so the button can't be pointed at javascript: or similar.
    def normalized_review_url
      raw = params[:google_review_url].to_s.strip
      return nil if raw.blank?
      raw = "https://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
      uri = URI.parse(raw)
      uri.is_a?(URI::HTTP) && uri.host.present? ? uri.to_s : nil
    rescue URI::InvalidURIError
      nil
    end

    def notify_member(rating)
      member = rating.member
      return if member.nil?
      title = t("customer.review_reply.notice_title", shop: current_workspace.name)
      body  = rating.reply_body.to_s.truncate(140)
      member.notifications.create!(workspace: current_workspace, kind: "promo",
                                   title: title, body: body, icon: "💬", deep_link: "/shop")
      PushJob.perform_later(current_workspace.id, [member.id], title, body, "/shop") if PushSender.configured?
    rescue => e
      Rails.logger.error("[Feedback] notify_member: #{e.class} #{e.message}")
    end
  end
end
