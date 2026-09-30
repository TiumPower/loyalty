module Customer
  class CodesController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    def show
      @member = current_member
      @token  = MemberQr.encode(@member)
      # The high-water mark the phone polls from. An id, not a timestamp: a
      # float timestamp does not survive the round trip (see #recent).
      @after_id = current_member.purchases.maximum(:id).to_i
    end

    # Fresh rotating QR (SVG) — polled by the countdown so a screenshot expires.
    def token
      color = current_workspace.theme_value(:ink).to_s.delete("#")
      svg = helpers.qr_svg(MemberQr.encode(current_member), color: color, size: 210)
      render json: { svg: svg, ttl: MemberQr::TTL }
    end

    # Poll for an earn newer than `after` so the phone can animate "+X".
    #
    # Keyed on the purchase id rather than on its timestamp. It used to send the
    # time back as a float and rebuild it with Time.at, which loses part of a
    # microsecond — so `created_at > since` stayed true for the very purchase
    # just reported, and the "+X points" burst reopened itself the moment the
    # customer dismissed it, forever.
    def recent
      after = params[:after].to_i
      p = current_member.purchases.not_voided.where("id > ?", after).order(:id).last
      if p
        render json: { earned: p.points_earned, balance: current_member.reload.points_balance,
                       id: p.id }
      else
        render json: { earned: nil }
      end
    end
  end
end
