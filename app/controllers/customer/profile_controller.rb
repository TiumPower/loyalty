module Customer
  class ProfileController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    # The design splits the account into a read-only summary and its own edit
    # screen; both render from the same member record.
    def edit
      @member = current_member
    end

    def show
      @member = current_member
    end

    def update
      @member = current_member
      attrs = profile_params
      raw_bday = params.dig(:member, :birthday).to_s.strip

      if raw_bday.present? && attrs[:birthday].nil?
        @member.assign_attributes(attrs.except(:birthday))
        @member.errors.add(:birthday, "không hợp lệ — nhập theo DD/MM/YYYY")
        return render :edit, status: :unprocessable_entity
      end

      # Email is the login identifier. There is no password, and signing in with
      # an unknown address silently creates a NEW member — so a typo here used
      # to strand the customer's points on an orphaned record and hand them an
      # empty account, with nothing to tell them what had happened. The new
      # address has to answer a code before it replaces the old one.
      new_email = Member.canonical_email(attrs[:email])
      changing  = new_email.present? && new_email != @member.email
      attrs = attrs.except(:email)

      if changing && (taken = Member.where.not(id: @member.id).exists?(email: new_email))
        @member.assign_attributes(attrs)
        @member.errors.add(:email, t("customer.profile.email_taken"))
        return render :edit, status: :unprocessable_entity
      end

      unless @member.update(attrs)
        return render :edit, status: :unprocessable_entity
      end

      return redirect_to member_profile_path, notice: t("customer.profile.updated") unless changing

      start_email_change!(new_email)
      redirect_to member_profile_confirm_email_path
    end

    # Step 2 of an email change — enter the code sent to the new address.
    def confirm_email
      @pending = session[:pending_email]
      return redirect_to member_profile_path if @pending.blank?
      load_challenge
    end

    def verify_email_change
      @pending = session[:pending_email]
      return redirect_to member_profile_path if @pending.blank?

      challenge = email_change_challenge
      case challenge&.verify(params[:code])
      when :ok
        # Re-check: someone may have claimed the address while the code was out.
        if Member.where.not(id: current_member.id).exists?(email: @pending)
          session.delete(:pending_email)
          return redirect_to member_profile_path, alert: t("customer.profile.email_taken")
        end
        current_member.update!(email: @pending)
        session.delete(:pending_email)
        redirect_to member_profile_path, notice: t("customer.profile.email_changed", email: @pending)
      else
        load_challenge
        flash.now[:alert] = t("customer.profile.email_code_bad")
        render :confirm_email, status: :unprocessable_entity
      end
    end

    def resend_email_change
      pending = session[:pending_email]
      return redirect_to member_profile_path if pending.blank?
      start_email_change!(pending)
      redirect_to member_profile_confirm_email_path, notice: t("customer.profile.email_code_sent")
    end

    # Save just the avatar (separate from the name/email/birthday form). The
    # attach was written with its result dropped, so a file the model refuses
    # still reported "Đã cập nhật ảnh đại diện".
    def avatar
      file = params.dig(:member, :avatar)
      unless file.respond_to?(:original_filename) # a real uploaded file, not a string
        return redirect_to member_profile_path, alert: "Vui lòng chọn ảnh."
      end
      member = current_member
      if member.avatar.attach(file)
        redirect_to member_profile_path, notice: "Đã cập nhật ảnh đại diện."
      else
        redirect_to member_profile_path,
                    alert: member.errors.full_messages.to_sentence.presence || "Không lưu được ảnh."
      end
    end

    private

    def start_email_change!(email)
      session[:pending_email] = email
      # `channel: "email"` is pinned, not inferred: the whole point of this flow
      # is to prove control of the NEW address, so routing the code to Zalo
      # would prove nothing.
      OtpChallenge.issue!(identifier: email, scope: "customer", workspace: current_workspace,
                          purpose: "email_change", channel: "email")
    end

    def email_change_challenge
      OtpChallenge.latest_for(identifier: @pending, scope: "customer",
                              workspace: current_workspace, purpose: "email_change")
    end

    # Whether to print the code on screen is the challenge's call — one rule,
    # shared with the login screen.
    def load_challenge
      @challenge = email_change_challenge
      @dev_code  = @challenge.code if @challenge&.show_on_screen?
    end

    # :avatar has its own action; leaving it here let the text form attach one
    # through a path that never looked at the result.
    def profile_params
      p = params.require(:member).permit(:name, :email, :phone, :birthday, :gender)
      p[:birthday] = parse_dmy(p[:birthday]) if p.key?(:birthday)
      p
    end

    # "01/03/1994" (or 1/3/1994, with - or .) → Date; nil if unparseable/blank.
    def parse_dmy(str)
      s = str.to_s.strip
      return nil if s.blank?
      d, m, y = s.split(%r{[/\-.]}).map { |x| x.to_i }
      Date.new(y, m, d)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
