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

      @voucher = voucher_for(params[:token])
      return render_token_problem if @voucher.nil? || @token_error
      render :confirm
    end

    # Step 2 — permanently mark the voucher used (anti-fraud lock).
    #
    # This used to resolve the voucher from a bare voucher_id in the form, so
    # the one-time code — the entire proof that the customer is standing at the
    # counter and agreed to spend it — was only ever checked in step 1. Any
    # staff login could POST an id and burn any customer's voucher in the shop,
    # never having seen their phone. The code is re-verified here, against the
    # same rules, and the id is only used to confirm the two agree.
    def create
      @voucher = voucher_for(params[:token])
      return render_token_problem if @voucher.nil? || @token_error

      if params[:voucher_id].present? && params[:voucher_id].to_s != @voucher.id.to_s
        @error = "Mã không khớp với ưu đãi. Khách vui lòng tạo lại mã."
        return render :search, status: :unprocessable_entity
      end

      if @voucher.mark_used!(outlet: current_outlet, staff: current_user)
        render :success
      else
        # Someone else consumed it between the check above and the write.
        render :used
      end
    end

    private

    def nav_key = :scanner

    # Resolve a voucher from a typed/scanned use code and decide whether it may
    # be consumed right now. Sets @token_error to the screen to show when not.
    def voucher_for(raw)
      @token_error = nil
      token = raw.to_s.gsub(/\D/, "")
      voucher = token.present? ? Voucher.where(redeem_token: token).first : nil

      if voucher.nil?
        @token_error = :invalid
      elsif voucher.state == "used"
        @token_error = :used
      elsif voucher.redeem_token_expires_at.nil? || voucher.redeem_token_expires_at < Time.current
        @token_error = :stale
      elsif voucher.expired?
        # The nightly sweep may not have flipped the row yet; the customer's
        # voucher is still past its own expiry date either way.
        @token_error = :expired
      end
      voucher
    end

    def render_token_problem
      return render :used if @token_error == :used
      @error = case @token_error
               when :stale   then "Mã sử dụng đã hết hiệu lực. Khách vui lòng tạo lại mã."
               when :expired then "Ưu đãi này đã hết hạn sử dụng."
               else "Mã không hợp lệ hoặc đã hết hạn."
               end
      render :search, status: :unprocessable_entity
    end
  end
end
