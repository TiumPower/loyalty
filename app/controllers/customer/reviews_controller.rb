module Customer
  # Public "About the shop" page (info, branches, all customers' feedback) and
  # the member's own reviews — a member may leave many and edit their own.
  class ReviewsController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    # How often one member can receive the automatic "sorry about that" reward.
    # Without this, a member could farm vouchers by leaving 1-star reviews.
    APOLOGY_COOLDOWN = 90.days

    # The shop's own page: where it is, when it opens, what it serves, and —
    # when the merchant allows it — what other customers said.
    #
    # The whole screen used to sit behind `feedback_public`, so a merchant who
    # only wanted to keep other people's reviews off the app also took away
    # their address, opening hours, amenities and menu. Those are two different
    # decisions; the switch now makes only the second one.
    def index
      @outlets = current_workspace.outlets.order(:id).to_a
      @public  = current_workspace.feedback_public?
      # A member's own reviews are their own: they can read and edit them even
      # when the public list is off, or there is no way back to something they
      # wrote.
      @mine     = Rating.where(member: current_member).recent.to_a
      @my_count = @mine.size

      unless @public
        @count, @avg, @dist, @ratings, @shown, @highlights = 0, 0, (1..5).index_with { 0 }, [], 0, []
        return
      end

      @count    = Rating.count
      @avg      = Rating.average(:stars)&.round(1) || 0
      # Star breakdown for the summary bars — one grouped count over the whole
      # table, not a tally of the hundred rows the list happens to show.
      counts    = Rating.group(:stars).count
      @dist     = (1..5).index_with { |n| counts[n].to_i }
      @ratings  = Rating.recent.includes(:member, :replied_by).limit(100).to_a
      # The design shows three reviews and a way to see the rest.
      @shown    = params[:all].present? ? @ratings.size : 3
      # "Review highlights": the tags customers picked most often, top three.
      counts    = Hash.new(0)
      Rating.where.not(tags: nil).pluck(:tags).each { |list| Array(list).each { |k| counts[k] += 1 if Rating::TAGS.include?(k) } }
      @highlights = counts.sort_by { |_, n| -n }.first(3).map { |k, _| t("customer.review.tag_#{k}") }
    end

    def new
      # Deliberately no default star count. Pre-selecting 5 meant anyone who
      # tapped "Gửi đánh giá" without touching the stars filed a 5-star review,
      # quietly inflating the public average every shop is judged on.
      @rating = Rating.new
    end

    def create
      @rating = Rating.new(workspace: current_workspace, member: current_member,
                           stars: stars_param, comment: comment_param, tags: tags_param)
      attach_photos(@rating)
      if @rating.save
        MerchantAlerts.new_rating(@rating)
        apology = maybe_apologise(@rating)
        # Rendering the thanks screen straight from this POST left the customer
        # staring at the untouched form: Turbo drops a 200 form response. Redirect.
        flash[:apology_voucher_id] = apology.id if apology
        redirect_to member_review_thanks_path(rating: @rating.id)
      else
        render :new, status: :unprocessable_entity
      end
    end

    # Landing page after a successful review (see #create).
    def thanks
      @rating = Rating.where(member: current_member).find_by(id: params[:rating])
      return redirect_to after_save_path unless @rating
      id = flash[:apology_voucher_id]
      @apology = id.present? ? Voucher.where(member: current_member).find_by(id: id) : nil
    end

    def edit
      @rating = own_rating or return redirect_to(after_save_path, alert: t("customer.review_reply.not_found"))
    end

    def update
      @rating = own_rating or return redirect_to(after_save_path, alert: t("customer.review_reply.not_found"))
      @rating.photos.purge_later if params[:remove_photos] == "1" && @rating.photos.attached?
      attach_photos(@rating)
      if @rating.update(stars: stars_param, comment: comment_param, tags: tags_param)
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

    # Photos of the visit. Attaching runs before save so the model validation
    # sees them; anything past the cap is dropped here rather than failing the
    # whole review, which would lose the words the customer just typed.
    def attach_photos(rating)
      files = Array(params[:photos]).reject(&:blank?).first(Rating::MAX_PHOTOS)
      return if files.empty?
      rating.photos.attach(files)
    end
    # The chips post whatever is in the DOM, so keep only keys we know.
    def tags_param = Array(params[:tags]).map(&:to_s) & Rating::TAGS
    def after_save_path = member_shop_about_path

    # An unhappy customer who gets something back on the spot often stays. Only
    # fires when the merchant configured it, and at most once per cooldown.
    def maybe_apologise(rating)
      cfg = current_workspace.automation(:low_rating)
      return nil unless cfg["enabled"] && cfg["reward_id"].present?
      return nil if rating.stars > (cfg["threshold"].presence || 3).to_i
      return nil if apologised_recently?

      reward = current_workspace.rewards.find_by(id: cfg["reward_id"])
      return nil unless reward
      # The last of the paths that handed out a voucher without checking the
      # merchant's stock. No apology gift is better than one that quietly
      # exceeds the limit they set.
      return nil unless reward.claim_stock!

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
