module Customer
  class ScanController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    def show
      @member = current_member
      # What a check-in is actually worth, and whether today's is already spent.
      # The screen used to promise "nhận điểm" without ever naming a number.
      @checkin_points = current_workspace.missions.active.where(mission_type: "checkin").sum(:reward_points)
      @checked_in_today = current_member.last_checkin_at&.to_date == Date.current
    end

    # Multi-purpose resolver (§6.2 POS earn + §6.6 promo claim). Reached from the
    # in-app camera or a deep-linked promo/POS QR.
    def resolve
      parse_code!(params[:code]) if params[:code].present?
      if params[:promo].present?
        handle_promo(params[:promo])
      elsif params[:pos].present?
        handle_pos(params[:pos])
      elsif params[:checkin].present?
        handle_checkin(params[:checkin])
      elsif params[:token].present?
        dispatch_token(params[:token])
      else
        invalid!
      end
    end


    # Confirm step for the screen above.
    def claim_pos
      @charge = current_workspace.pos_charges.find_by(token: params[:token].to_s)
      return invalid! unless @charge
      @result, err = @charge.claim!(current_member)
      case err
      when nil      then render :earn_success
      when :used    then render :pos_used, status: :unprocessable_entity
      when :expired then render :pos_expired, status: :unprocessable_entity
      else invalid!
      end
    end

    private

    # ---- Store check-in (scan the on-site QR) ----
    def handle_checkin(token)
      ok, outlet_id = Checkin.decode(token, workspace: current_workspace)
      return invalid! unless ok
      outlet = outlet_id.present? ? current_workspace.outlets.find_by(id: outlet_id) : nil
      status, points = Checkin.check_in!(current_member, current_workspace, outlet)
      @points = points
      # Which branch they checked in at — the success screen names it, as the
      # design's receipt card does.
      @outlet = outlet
      case status
      when :done    then render :checkin_success
      when :already then render :checkin_already, status: :unprocessable_entity
      else render :checkin_none, status: :unprocessable_entity
      end
    end

    # ---- Promo claim-to-wallet (§6.6) ----
    def handle_promo(token)
      @promo = current_workspace.promo_codes.find_by(token: token)
      return invalid! unless @promo
      @promo.register_scan!
      @voucher, err = @promo.claim!(current_member)
      case err
      when nil      then notify_claim(@voucher); render :claim_success
      when :already then render :claim_already
      else render :claim_unavailable, status: :unprocessable_entity
      end
    end

    # Drop a persistent inbox notification so the claimed reward isn't only on
    # the one-time success screen (also nudges the wallet "Khả dụng" badge).
    def notify_claim(voucher)
      return unless voucher
      MemberNotifier.notify(current_member, "claim_reward", icon: "🎁",
                            link: "/vouchers/#{voucher.id}", reward: voucher.reward&.title)
    end

    # ---- POS self-scan earn (§6.2) ----
    # Scanning only READS the bill: the design shows what was found and what it
    # is worth, and the customer presses "Add points". Claiming straight off the
    # scan gave no chance to notice the wrong bill had been scanned.
    def handle_pos(token)
      @charge = current_workspace.pos_charges.find_by(token: token)
      return invalid! unless @charge
      return render(:pos_used, status: :unprocessable_entity)    if @charge.state == "claimed"
      return render(:pos_expired, status: :unprocessable_entity) if @charge.expired?
      @points = estimated_points(@charge)
      render :pos_preview
    end

    # What the bill is worth before it is claimed, using the same rate and tier
    # multiplier EarnPoints will apply.
    def estimated_points(charge)
      prog = current_program
      base = prog.points_for(charge.amount)
      mult = (prog.tiers_enabled ? (current_member.tier&.multiplier || 1) : 1).to_f
      (base * mult).floor
    end

    def invalid!
      @message = t("customer.scan.invalid_message")
      render :invalid, status: :unprocessable_entity
    end

    def dispatch_token(token)
      if PromoCode.exists?(token: token) then handle_promo(token)
      elsif PosCharge.exists?(token: token) then handle_pos(token)
      else invalid!
      end
    end

    # Accept a bare token or a scanned URL carrying promo=/pos=.
    def parse_code!(raw)
      s = raw.to_s.strip
      if s =~ /[?&]promo=([^&]+)/ then params[:promo] = $1
      elsif s =~ /[?&]pos=([^&]+)/ then params[:pos] = $1
      elsif s =~ /[?&]checkin=([^&]+)/ then params[:checkin] = CGI.unescape($1)
      else params[:token] = s[%r{/([A-Za-z0-9]+)\z}, 1] || s
      end
    end
  end
end
