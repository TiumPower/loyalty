module Merchant
  # Public self-serve merchant registration. Creates a workspace (its own
  # subdomain), an owner, and default loyalty config, then signs the owner in.
  class SignupsController < ApplicationController
    layout "marketing"

    RESERVED = TenantResolver::RESERVED_SUBDOMAINS

    def new
      redirect_to(merchant_root_path) and return if user_signed_in?
      @workspace = Workspace.new(industry: "fnb")
    end

    def create
      @workspace = Workspace.new(workspace_params)
      @workspace.status     = "trial"    # self-serve: live immediately, no approval gate
      @workspace.paid_until = Workspace::TRIAL_DAYS.days.from_now
      @workspace.plan       = "starter"
      @workspace.theme  = AppearancesController::PRESETS.dig(preset_for(@workspace.industry), "theme") || {}
      @email = params[:email].to_s.downcase.strip
      @name  = params[:owner_name].presence || "Chủ cửa hàng"

      if reserved_subdomain?
        @workspace.errors.add(:subdomain, "không sử dụng được, vui lòng chọn tên khác")
        return render :new, status: :unprocessable_entity
      end
      unless valid_signup?
        return render :new, status: :unprocessable_entity
      end

      ActiveRecord::Base.transaction do
        @workspace.save!
        owner = existing_user
        if owner.nil?
          owner = User.new(email: @email, name: @name, password: params[:password], locale: "vi")
          owner.save!
        end
        ActsAsTenant.with_tenant(@workspace) do
          @workspace.memberships.create!(user: owner, role: "owner")
        end
        WorkspaceBootstrap.call(@workspace)
        sign_in(:user, owner)
        session[:workspace_id] = @workspace.id
      end
      # Notify super admins of the new signup (never block signup on mail).
      begin
        AdminMailer.new_workspace(@workspace).deliver_later
      rescue => e
        Rails.logger.error("[Signup] admin notify failed: #{e.class} #{e.message}")
      end
      redirect_to merchant_url_for(@workspace), allow_other_host: true,
                  notice: "Chào mừng! Bạn đang dùng thử #{Workspace::TRIAL_DAYS} ngày miễn phí — bắt đầu thiết lập cửa hàng ngay."
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_entity
    end

    private

    def workspace_params
      params.require(:workspace).permit(:name, :subdomain, :industry)
    end

    def reserved_subdomain?
      RESERVED.include?(@workspace.subdomain.to_s.downcase)
    end

    # The account that already owns this email, if any. Memoized so the password
    # check and the create path agree on one object.
    def existing_user
      return @existing_user if defined?(@existing_user)
      @existing_user = User.find_by(email: @email)
    end

    def valid_signup?
      ok = @workspace.valid?
      # "Subdomain đã tồn tại" left the owner to guess another one. Offer a free
      # address built from what they typed so the form can be finished in a tap.
      if @workspace.errors.of_kind?(:subdomain, :taken)
        @suggested_subdomain = free_subdomain_near(@workspace.subdomain)
      end
      if @email.blank? || !@email.include?("@")
        @workspace.errors.add(:base, "Email không hợp lệ"); ok = false
      end
      if params[:password].to_s.length < 6
        @workspace.errors.add(:base, "Mật khẩu tối thiểu 6 ký tự"); ok = false
      end
      # SECURITY: an existing account may open a second shop, but ONLY after
      # proving the password. Without this check anyone who knows a merchant's
      # email could sign up with it and be signed straight into that account.
      # The message does say the email is taken (merchants need to know to go and
      # log in instead); the rate limit on /merchant/signup is what stops this
      # form being used to guess passwords or harvest addresses.
      if ok && existing_user && !existing_user.valid_password?(params[:password].to_s)
        @workspace.errors.add(:base,
          "Email này đã có tài khoản. Vui lòng đăng nhập bằng mật khẩu của tài khoản đó, " \
          "hoặc dùng email khác để mở cửa hàng mới.")
        ok = false
      end
      ok
    end

    # First free variant of `base`: base2, base3, … (capped so a pathological
    # case cannot spin).
    def free_subdomain_near(base)
      base = base.to_s
      return nil if base.blank?
      ActsAsTenant.without_tenant do
        (2..30).each do |n|
          candidate = "#{base}#{n}"
          next if RESERVED.include?(candidate)
          return candidate unless Workspace.exists?(subdomain: candidate)
        end
      end
      nil
    end

    def preset_for(industry)
      { "fnb" => "cozy_cafe", "service" => "modern_beauty", "retail" => "retail_bold" }[industry] || "cozy_cafe"
    end
  end
end
