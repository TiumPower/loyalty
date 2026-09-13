module Merchant
  class BroadcastsController < BaseController
    before_action :require_manager!, except: [:index]

    def index
      @broadcasts = current_workspace.broadcasts.recent.to_a
    end

    def new
      load_audience(params[:segment], params[:outlet], params[:q], params[:tier])
      @count     = @audience_scope.count
      @broadcast = Broadcast.new(segment_key: @segment)
    end

    def create
      bp = params[:broadcast] || {}
      load_audience(bp[:segment_key], bp[:audience_outlet_id], bp[:audience_query], bp[:audience_tier])
      @broadcast = current_workspace.broadcasts.new(
        broadcast_params.merge(segment_key: @segment, created_by: current_user,
                               audience_label: @audience_label,
                               audience_outlet_id: @outlet&.id, audience_query: @q.presence,
                               audience_tier: @tier)
      )
      members = @audience_scope.to_a
      @count  = members.size

      if members.empty?
        @broadcast.errors.add(:base, "Nhóm khách này chưa có ai — không thể gửi.")
        return render :new, status: :unprocessable_entity
      end

      sched = parse_schedule(params[:scheduled_at])
      if sched && sched > Time.current
        @broadcast.scheduled_at = sched
        if @broadcast.save
          return redirect_to merchant_broadcasts_path,
                             notice: "Đã lên lịch gửi vào #{l(sched, format: :short)}."
        end
      elsif @broadcast.save
        @broadcast.deliver!(members)
        return redirect_to merchant_broadcasts_path, notice: "Đã gửi tới #{@broadcast.sent_count} khách."
      end
      render :new, status: :unprocessable_entity
    end

    # Call back a scheduled send. Scheduling existed with no way to undo it, so a
    # manager who changed their mind could only watch it go out to every
    # customer's phone. Only ever removes something not yet delivered; a sent
    # broadcast is a record of what customers received.
    def destroy
      broadcast = current_workspace.broadcasts.find(params[:id])
      if broadcast.sent_at.present?
        return redirect_to merchant_broadcasts_path, alert: t("merchant.broadcasts.cancel_too_late")
      end
      # Claim it first so the delivery job cannot pick it up mid-cancel.
      if broadcast.claim_for_delivery!
        broadcast.destroy
        redirect_to merchant_broadcasts_path, notice: t("merchant.broadcasts.cancelled")
      else
        redirect_to merchant_broadcasts_path, alert: t("merchant.broadcasts.cancel_too_late")
      end
    end

    private

    def nav_key = :broadcasts

    # Resolve the filtered audience (segment + branch + search) once, and build the
    # display name, from whichever params the request carries (query on :new, nested
    # broadcast[...] hidden fields on :create). Sets @segment, @outlet, @q,
    # @audience_scope and @audience_label.
    def load_audience(segment, outlet_id, q, tier = nil)
      @segment = MemberSegments::PRESETS.key?(segment) ? segment : "all"
      @outlet  = current_workspace.outlets.find_by(id: outlet_id) if outlet_id.present?
      @q       = q.to_s.strip
      @tier    = tier.presence if current_workspace.tiers.any? { |t| t.key == tier }
      @audience_scope = MemberSegments.audience(segment: @segment, outlet_id: @outlet&.id, q: @q, tier: @tier)
      @audience_label = MemberSegments.audience_label(segment: @segment, outlet: @outlet, q: @q, tier: @tier)
    end

    def broadcast_params
      params.require(:broadcast).permit(:title, :body)
    end

    def parse_schedule(raw)
      return nil if raw.blank?
      Time.zone.parse(raw.to_s)
    rescue ArgumentError
      nil
    end
  end
end
