module Merchant
  class RedeemController < BaseController
    # Step 1 — resolve the voucher from a scanned/typed use code (§6.4).
    def lookup
      # Staff may scan a member's personal QR here by mistake. Auto-route it to
      # the earn flow so a single scan "just works".
      if (member = ScanRouter.member(params[:token], current_workspace))
        @member = member
        # This renders the earn form, which needs its own idempotency key —
        # without one, awarding from this path had no double-tap protection.
        @earn_key = SecureRandom.uuid
        return render "merchant/earn/lookup"
      end

      token = params[:token].to_s.gsub(/\D/, "")
      @voucher = token.present? ? Voucher.where(redeem_token: token).first : nil

      if @voucher.nil?
        @error = "Mã không hợp lệ hoặc đã hết hạn."
        render :search, status: :unprocessable_entity
      elsif @voucher.state == "used"
        render :used   # already-used warning (with time)
      elsif @voucher.redeem_token_expires_at.nil? || @voucher.redeem_token_expires_at < Time.current
        @error = "Mã sử dụng đã hết hiệu lực. Khách vui lòng tạo lại mã."
        render :search, status: :unprocessable_entity
      else
        render :confirm
      end
    end

    # Step 2 — permanently mark the voucher used (anti-fraud lock).
    def create
      @voucher = Voucher.find_by(id: params[:voucher_id])
      if @voucher.nil?
        @error = "Không tìm thấy ưu đãi."
        render :search, status: :unprocessable_entity
      elsif @voucher.state == "used"
        render :used
      elsif @voucher.mark_used!(outlet: current_outlet, staff: current_user)
        render :success
      else
        # Someone else consumed it between the check above and the write.
        render :used
      end
    end

    private

    def nav_key = :scanner
  end
end
