module Customer
  class SessionsController < BaseController
    before_action :require_workspace!

    # Referral join link: stash the code, then go to login.
    def join
      # Referral reward is for NEW members only. An existing member of this shop
      # scanning the shop's own referral gets a clear notice instead of a login
      # prompt / claim they can't receive.
      if member_signed_in? && current_member&.workspace_id == current_workspace.id
        return redirect_to member_root_path, alert: t("customer.referrals.only_new_members")
      end
      session[:ref_code] = params[:code].to_s.upcase
      redirect_to member_login_path, notice: t("customer.referrals.login_to_claim")
    end

    # Step 1 — enter email
    def new
      redirect_to(member_root_path) and return if member_signed_in? && current_member.workspace_id == current_workspace.id
      @email = ""
    end

    # Step 1 submit — issue OTP, go to verify screen
    def create
      @email = normalize(params[:email])
      unless @email&.match?(URI::MailTo::EMAIL_REGEXP)
        flash.now[:alert] = "Vui lòng nhập email hợp lệ."
        return render :new, status: :unprocessable_entity
      end
      OtpChallenge.issue!(workspace: current_workspace, email: @email)
      session[:otp_email] = @email
      redirect_to member_verify_path
    end

    # Step 2 — enter OTP
    def verify_form
      @email = session[:otp_email]
      redirect_to(member_login_path) and return if @email.blank?
      @dev_code = latest_dev_code(@email) if show_otp_onscreen?
    end

    # Step 2 submit — check OTP, sign in (create member on first login)
    def verify
      @email = session[:otp_email]
      redirect_to(member_login_path) and return if @email.blank?

      challenge = OtpChallenge.where(workspace: current_workspace, email: @email, purpose: "login")
                              .order(created_at: :desc).first
      result = challenge&.verify(params[:code])

      if result == :ok
        member = Member.find_by(workspace: current_workspace, email: @email)
        is_new = member.nil?
        if is_new && !current_workspace.can_add_member?
          flash.now[:alert] = "Chương trình đang tạm đầy. Vui lòng quay lại sau."
          return render :verify_form, status: :unprocessable_entity
        end
        # Attribution is captured at creation — where a member came from can't be
        # reconstructed later, and it's what tells the merchant which acquisition
        # channel is actually working.
        member ||= Member.create!(workspace: current_workspace, email: @email,
                                  join_source: join_source_for(session[:ref_code]))
        # Referral rewards apply ONLY to brand-new members.
        ref_code = session.delete(:ref_code)
        Referrals.attach(referred: member, referrer_code: ref_code) if is_new && ref_code.present?
        Automations.on_signup(member) if is_new
        session.delete(:otp_email)
        sign_in_member(member)             # per-shop long-lived cookie
        # Resume a stashed target (e.g. the promo QR they scanned) so the reward
        # is claimed right after login; otherwise land on home.
        target = session.delete(:return_to).presence || member_root_path
        welcome = is_new ? "Chào mừng bạn đến với #{current_workspace.name} 👋" : "#{current_workspace.name} chào mừng bạn 👋"
        redirect_to target, notice: welcome
      else
        @dev_code = latest_dev_code(@email) if show_otp_onscreen?
        flash.now[:alert] = otp_error_message(result)
        render :verify_form, status: :unprocessable_entity
      end
    end

    def destroy
      sign_out_member
      redirect_to member_login_path, notice: "Đã đăng xuất."
    end

    private

    # Which channel brought this member in. The referral code is stashed by #join;
    # everything else is inferred from the page they were trying to reach when we
    # asked them to log in (a scanned promo QR, the shop's check-in poster, a POS
    # bill QR). Anything else is a plain visit.
    def join_source_for(ref_code)
      return "referral" if ref_code.present?
      target = session[:return_to].to_s
      return "campaign" if target.include?("promo=")
      return "checkin"  if target.include?("checkin=")
      return "pos"      if target.include?("pos=")
      "direct"
    end

    def normalize(email)
      # Canonicalize (gmail dots + "+tag") so the OTP + member lookup match the
      # stored canonical email and alias tricks can't farm rewards.
      Member.canonical_email(email)
    end

    # Show the code on-screen in dev, when explicitly enabled, or until an email
    # delivery provider (SMTP) is configured.
    def show_otp_onscreen?
      AppSetting.show_otp? || ENV["SHOW_OTP"] == "true" ||
        !Rails.env.production? || !EmailOtp.configured?
    end

    def latest_dev_code(email)
      OtpChallenge.where(workspace: current_workspace, email: email).order(created_at: :desc).first&.code
    end

    def otp_error_message(result)
      case result
      when :expired  then "Mã đã hết hạn. Vui lòng gửi lại."
      when :too_many then "Nhập sai quá nhiều lần. Vui lòng gửi lại mã."
      else "Mã xác thực không đúng."
      end
    end
  end
end
