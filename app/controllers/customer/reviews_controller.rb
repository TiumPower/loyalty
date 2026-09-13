module Customer
  # Public "About the shop" page (info, branches, all customers' feedback) and
  # the member's own reviews — a member may leave many and edit their own.
  class ReviewsController < BaseController
    before_action :require_workspace!
    before_action :require_member!
    before_action :ensure_public!, only: [:index]

    # How often one member can receive the automatic "sorry about that" reward.
    # Without this, a member could farm vouchers by leaving 1-star reviews.
    APOLOGY_COOLDOWN = 90.days

    def index
      @outlets  = current_workspace.outlets.order(:id).to_a
      @count    = Rating.count
      @avg      = Rating.average(:stars)&.round(1) || 0
      @ratings  = Rating.recent.includes(:member, :replied_by).limit(100).to_a
      @mine     = Rating.where(member: current_member).recent.to_a
      @my_count = @mine.size
    end

    def new
      # Deliberately no default star count. Pre-selecting 5 meant anyone who
      # tapped "Gửi đánh giá" without touching the stars filed a 5-star review,
      # quietly inflating the public average every shop is judged on.
      @rating = Rating.new
    end

    def create
      @rating = Rating.new(workspace: current_workspace, member: current_member,
                           stars: stars_param, comment: comment_param)
      if @rating.save
        MerchantAlerts.new_rating(@rating)
        @apology = maybe_apologise(@rating)
        render :thanks
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @rating = own_rating or return redirect_to(after_save_path, alert: t("customer.review_reply.not_found"))
    end

    def update
      @rating = own_rating or return redirect_to(after_save_path, alert: t("customer.review_reply.not_found"))
      if @rating.update(stars: stars_param, comment: comment_param)
        redirect_to after_save_path, notice: t("customer.review_reply.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def own_rating = Rating.where(member: current_member).find_by(id: params[:id])
    # nil, not 1, when nothing was chosen: clamping an empty field to 1 turned
    # "I forgot to tap a star" into the harshest possible review. The model's
    # inclusion validation then asks for a real choice.
    def stars_param
      n = params[:stars].to_i
      n.between?(1, 5) ? n : nil
    end
    def comment_param = params[:comment].to_s.strip.presence
    def after_save_path = current_workspace.feedback_public? ? member_shop_about_path : member_profile_path

    def ensure_public!
      redirect_to member_root_path, alert: t("customer.review_reply.unavailable") unless current_workspace.feedback_public?
    end

    # An unhappy customer who gets something back on the spot often stays. Only
    # fires when the merchant configured it, and at most once per cooldown.
    def maybe_apologise(rating)
      cfg = current_workspace.automation(:low_rating)
      return nil unless cfg["enabled"] && cfg["reward_id"].present?
      return nil if rating.stars > (cfg["threshold"].presence || 3).to_i
      return nil if apologised_recently?

      reward = current_workspace.rewards.find_by(id: cfg["reward_id"])
      return nil unless reward

      voucher = Voucher.create!(workspace: current_workspace, member: current_member,
                                reward: reward, source: "campaign", state: "active",
                                points_spent: 0, expires_at: reward.voucher_expiry_from)
      current_member.update_columns(
        settings: current_member.settings.merge("apology_at" => Time.current.iso8601)
      )
      current_member.notifications.create!(
        workspace: current_workspace, kind: "reward",
        title: t("customer.review_thanks.apology_notice_title"),
        body: t("customer.review_thanks.apology_notice_body", title: reward.title),
        icon: "🎁", deep_link: "/vouchers/#{voucher.id}"
      )
      voucher
    rescue => e
      Rails.logger.error("[Reviews] apology: #{e.class} #{e.message}")
      nil
    end

    def apologised_recently?
      at = current_member.settings["apology_at"]
      at.present? && Time.parse(at) > APOLOGY_COOLDOWN.ago
    rescue ArgumentError, TypeError
      false
    end
  end
end
