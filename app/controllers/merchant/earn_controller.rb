module Merchant
  class EarnController < BaseController
    # Step 1 — resolve the customer (scanned QR token, or manual phone entry).
    def lookup
      # Staff may scan a reward use-code (numeric voucher token) here by mistake.
      # Auto-route it to the verify flow so a single scan "just works".
      if (redirect = ScanRouter.reward_use_code(params[:token], current_workspace))
        @voucher = redirect
        return render_voucher_verify
      end

      @member = find_member
      if @member
        # One key per lookup: every scan of a customer gets its own, and every
        # submit of that form carries it, so a repeat submit is recognisable.
        @earn_key = SecureRandom.uuid
        render :lookup
      else
        @error = params[:token].present? ? "Mã không hợp lệ hoặc đã hết hạn." : "Không tìm thấy khách với email/SĐT này."
        render :search, status: :unprocessable_entity
      end
    end

    # Step 2 — award points for the entered bill amount.
    def create
      @member = Member.find_by(id: params[:member_id])
      amount  = params[:amount].to_s.gsub(/[^\d]/, "").to_i
      if @member.nil?
        @error = "Phiên đã hết hạn, vui lòng quét lại."
        return render :search, status: :unprocessable_entity
      end
      if amount <= 0
        @error = "Vui lòng nhập số tiền hoá đơn hợp lệ."
        # Keep the same key across a correction, so fixing a typo and
        # resubmitting is still the same single award.
        @earn_key = params[:earn_key].presence || SecureRandom.uuid
        return render :lookup, status: :unprocessable_entity
      end

      @result = EarnPoints.new(
        member: @member, amount: amount,
        outlet: current_outlet, staff: current_user, source: "staff_scan",
        idempotency_key: params[:earn_key].presence
      ).call
      render :create
    end

    private

    def nav_key = :scanner

    def find_member
      return MemberQr.decode(params[:token], workspace: current_workspace) if params[:token].present?

      # One box for both. The form used to be type="email" only, so a customer
      # at the counter had to spell out an address even though looking up by
      # phone already worked — and members imported with a phone and no email
      # could not be found manually at all.
      raw = params[:q].presence || params[:email].presence || params[:phone].presence
      return nil if raw.blank?
      raw = raw.to_s.strip
      if raw.include?("@")
        Member.find_by(email: Member.canonical_email(raw))
      else
        digits = raw.gsub(/[^\d]/, "")
        digits.present? ? Member.find_by(phone: digits) : nil
      end
    end

    # Render the reward-verify result (redeem flow) inside the scan_tool frame,
    # even though staff started on the "Tích điểm" tab.
    def render_voucher_verify
      if @voucher.state == "used"
        render "merchant/redeem/used"
      elsif @voucher.redeem_token_expires_at.nil? || @voucher.redeem_token_expires_at < Time.current
        @error = "Mã sử dụng đã hết hiệu lực. Khách vui lòng tạo lại mã."
        render "merchant/redeem/search", status: :unprocessable_entity
      elsif @voucher.expired?
        @error = "Ưu đãi này đã hết hạn sử dụng."
        render "merchant/redeem/search", status: :unprocessable_entity
      else
        render "merchant/redeem/confirm"
      end
    end
  end
end
