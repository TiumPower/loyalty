module Customer
  # Member login: phone + OTP by default, with email + OTP kept for the accounts
  # that were created before phone login existed.
  #
  # Both tabs post to this one action. The tab is INFERRED from the params when
  # it isn't given (`phone` present → phone, otherwise email) rather than being
  # required, so a bare `post "/login", params: { email: ... }` keeps working.
  class SessionsController < BaseController
    before_action :require_workspace!

    LOGIN_TABS = %w[phone email].freeze

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

    # Step 1 — enter a phone number (or an email)
    def new
      redirect_to(member_root_path) and return if member_signed_in? && current_member.workspace_id == current_workspace.id
      @tab   = requested_tab
      @phone = ""
      @email = ""
    end

    # Step 1 submit — issue OTP, go to verify screen
    def create
      @tab = requested_tab(infer: true)
      identifier, error = resolve_identifier
      if error
        flash.now[:alert] = error
        return render :new, status: :unprocessable_entity
      end

      OtpChallenge.issue!(identifier: identifier, scope: "customer", workspace: current_workspace)
      session[:otp_identifier] = identifier
      redirect_to member_verify_path
    end

    # Step 2 — enter OTP
    def verify_form
      @identifier = pending_identifier
      redirect_to(member_login_path) and return if @identifier.blank?
      load_challenge
    end

    # Step 2 submit — check OTP, sign in (create member on first login)
    def verify
      @identifier = pending_identifier
      redirect_to(member_login_path) and return if @identifier.blank?

      challenge = OtpChallenge.latest_for(identifier: @identifier, scope: "customer",
                                          workspace: current_workspace)
      result = challenge&.verify(params[:code])

      if result == :ok
        member = Member.find_by(workspace: current_workspace, identifier_key => @identifier)
        is_new = member.nil?
        if is_new && !current_workspace.can_add_member?
          flash.now[:alert] = "Chương trình đang tạm đầy. Vui lòng quay lại sau."
          load_challenge
          return render :verify_form, status: :unprocessable_entity
        end
        # Attribution is captured at creation — where a member came from can't be
        # reconstructed later, and it's what tells the merchant which acquisition
        # channel is actually working.
        member ||= Member.create!(workspace: current_workspace,
                                  identifier_key => @identifier,
                                  join_source: join_source_for(session[:ref_code]))
        # Referral rewards apply ONLY to brand-new members.
        ref_code = session.delete(:ref_code)
        Referrals.attach(referred: member, referrer_code: ref_code) if is_new && ref_code.present?
        Automations.on_signup(member) if is_new
        session.delete(:otp_identifier)
        session.delete(:otp_email)
        sign_in_member(member)             # per-shop long-lived cookie
        # Resume a stashed target (e.g. the promo QR they scanned) so the reward
        # is claimed right after login; otherwise land on home.
        target = session.delete(:return_to).presence || member_root_path
        welcome = is_new ? "Chào mừng bạn đến với #{current_workspace.name} 👋" : "#{current_workspace.name} chào mừng bạn 👋"
        redirect_to target, notice: welcome
      else
        load_challenge
        flash.now[:alert] = otp_error_message(result)
        render :verify_form, status: :unprocessable_entity
      end
    end

    def destroy
      sign_out_member
      redirect_to member_login_path, notice: "Đã đăng xuất."
    end

    private

    def requested_tab(infer: false)
      return params[:tab] if LOGIN_TABS.include?(params[:tab])
      return "email" if infer && params[:phone].blank? && params[:email].present?
      "phone"
    end

    # Returns [identifier, error_message]. The identifier is already canonical,
    # so it matches both the stored member and any earlier challenge.
    def resolve_identifier
      if @tab == "phone"
        @phone = Member.canonical_phone(params[:phone])
        @email = params[:email].to_s
        return [nil, t("customer.session.phone_invalid")] unless @phone&.match?(/\A0\d{8,10}\z/)
        [@phone, nil]
      else
        @email = Member.canonical_email(params[:email])
        @phone = params[:phone].to_s
        return [nil, t("customer.session.email_invalid")] unless @email&.match?(URI::MailTo::EMAIL_REGEXP)
        [@email, nil]
      end
    end

    # `otp_email` is the pre-phone-login session key. Reading it too keeps
    # anyone who was mid-login across the deploy from hitting a dead end; it can
    # go once a release has shipped.
    def pending_identifier
      session[:otp_identifier].presence || session[:otp_email].presence
    end

    def identifier_key = @identifier.to_s.include?("@") ? :email : :phone

    # The challenge drives both screens: whether to print the code, and whether
    # to explain a failed send.
    def load_challenge
      @challenge = OtpChallenge.latest_for(identifier: @identifier, scope: "customer",
                                           workspace: current_workspace)
      @dev_code  = @challenge.code if @challenge&.show_on_screen?
    end

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

    def otp_error_message(result)
      case result
      when :expired  then "Mã đã hết hạn. Vui lòng gửi lại."
      when :too_many then "Nhập sai quá nhiều lần. Vui lòng gửi lại mã."
      else "Mã xác thực không đúng."
      end
    end
  end
end
