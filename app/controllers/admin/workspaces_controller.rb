module Admin
  class WorkspacesController < BaseController
    before_action :set_workspace, only: [:show, :update, :approve, :suspend, :reactivate, :destroy]

    PRESET_BY_INDUSTRY = { "fnb" => "cozy_cafe", "service" => "modern_beauty", "retail" => "retail_bold" }.freeze

    def index
      ActsAsTenant.without_tenant do
        scope = Workspace.order(created_at: :desc)
        @status = params[:status] if Workspace::STATUSES.include?(params[:status])
        scope = scope.where(status: @status) if @status
        all = scope.to_a
        @counts = Workspace.group(:status).count
        # Payment filter (computed in Ruby — payment_state isn't a column).
        @payment = params[:payment].to_sym if Workspace::PAYMENT_STATES.map(&:to_s).include?(params[:payment])
        @pay_counts = all.group_by(&:payment_state).transform_values(&:size)
        all = all.select { |w| w.payment_state == @payment } if @payment
        @workspaces = all
      end
    end

    def new
      @workspace = Workspace.new(industry: "fnb", status: "active", plan: "starter")
    end

    # Admin creates a workspace + its owner login + default loyalty config.
    def create
      @workspace = Workspace.new(create_params)
      @workspace.status ||= "active"
      @workspace.plan   ||= "starter"
      @workspace.theme  = preset_theme(@workspace.industry)
      @workspace.branding = { "customer_term" => "bạn", "tagline" => "Chương trình tri ân khách hàng" }
      @workspace.settings = { "onboarded" => true }
      @email = params[:owner_email].to_s.downcase.strip
      @owner_name = params[:owner_name].presence || "Chủ #{@workspace.name}"
      @password = params[:owner_password].presence || SecureRandom.alphanumeric(10)

      unless valid_admin_create?
        return render :new, status: :unprocessable_entity
      end

      owner = nil
      new_owner = false
      ActiveRecord::Base.transaction do
        @workspace.save!
        owner = User.find_or_initialize_by(email: @email)
        new_owner = owner.new_record?
        if new_owner
          owner.assign_attributes(name: @owner_name, password: @password, locale: "vi")
          owner.save!
        end
        ActsAsTenant.with_tenant(@workspace) { @workspace.memberships.create!(user: owner, role: "owner") }
        WorkspaceBootstrap.call(@workspace)
      end

      # The password used to go into flash[:notice], which stash_toast_cookie
      # copies verbatim into a JS-readable cookie — a working shop-owner
      # credential sitting in document.cookie. It also showed a freshly
      # generated password even when the account already existed and kept its
      # old one, so the operator handed the customer a password that never
      # worked. Only :notice and :alert reach that cookie, so the credential
      # travels in its own flash key and is rendered once, in the page.
      if !new_owner
        redirect_to admin_workspace_path(@workspace),
          notice: "Đã tạo workspace #{@workspace.name}. Owner #{@email} đã có tài khoản — dùng mật khẩu sẵn có."
      elsif EmailOtp.configured?
        token = owner.send(:set_reset_password_token)
        StaffMailer.invite(owner, @workspace, token).deliver_later
        redirect_to admin_workspace_path(@workspace),
          notice: "Đã tạo workspace #{@workspace.name}. Email đặt mật khẩu đã gửi tới #{@email}."
      else
        flash[:owner_credentials] = { "email" => @email, "password" => @password }
        redirect_to admin_workspace_path(@workspace),
          notice: "Đã tạo workspace #{@workspace.name}."
      end
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_entity
    end

    def show
      ActsAsTenant.with_tenant(@workspace) do
        @members_count = Member.count
        @points_issued = PointTransaction.credits.sum(:amount)
        @program = @workspace.program
      end
    end

    def update
      if @workspace.update(update_params)
        redirect_to admin_workspace_path(@workspace), notice: "Đã cập nhật workspace."
      else
        ActsAsTenant.with_tenant(@workspace) do
          @members_count = Member.count
          @points_issued = PointTransaction.credits.sum(:amount)
          @program = @workspace.program
        end
        render :show, status: :unprocessable_entity
      end
    end

    def approve    = transition("active",    "Đã duyệt workspace.")
    def suspend    = transition("suspended", "Đã tạm ngưng workspace.")
    def reactivate = transition("active",    "Đã kích hoạt lại workspace.")

    # Permanently delete a workspace and ALL its data (irreversible).
    #
    # This is the most destructive action in the product — a paying customer's
    # members, points, vouchers, invoices and uploaded files, gone. It used to
    # be a button in the workspace LIST, one row among many, behind a browser
    # confirm() that Enter dismisses. Deleting now happens from the workspace's
    # own page and requires typing its subdomain, checked here rather than only
    # in the form, so a stray or replayed POST cannot purge a shop either.
    def destroy
      typed = params[:confirm].to_s.strip.downcase
      if typed != @workspace.subdomain.to_s.downcase
        return redirect_to admin_workspace_path(@workspace),
          alert: "Chưa xoá: cần gõ đúng subdomain “#{@workspace.subdomain}” để xác nhận."
      end
      name = @workspace.name
      WorkspacePurge.call(@workspace)
      redirect_to admin_workspaces_path,
                  notice: "Đã xoá vĩnh viễn workspace “#{name}” và toàn bộ dữ liệu liên quan."
    end

    private

    def nav_key = :workspaces

    def set_workspace
      ActsAsTenant.without_tenant { @workspace = Workspace.friendly.find(params[:id]) }
    end

    def transition(status, msg)
      @workspace.update!(status: status)
      redirect_back fallback_location: admin_workspaces_path, notice: msg
    end

    def create_params
      params.require(:workspace).permit(:name, :subdomain, :industry, :status, :plan, :locale_default)
    end

    def update_params
      params.require(:workspace).permit(:name, :subdomain, :custom_domain, :industry, :status, :plan, :locale_default)
    end

    def preset_theme(industry)
      key = PRESET_BY_INDUSTRY[industry] || "cozy_cafe"
      Merchant::AppearancesController::PRESETS.dig(key, "theme") || {}
    end

    def valid_admin_create?
      ok = @workspace.valid?
      if TenantResolver::RESERVED_SUBDOMAINS.include?(@workspace.subdomain.to_s.downcase)
        @workspace.errors.add(:subdomain, "không sử dụng được (đã dành riêng)"); ok = false
      end
      if @email.blank? || !@email.include?("@")
        @workspace.errors.add(:base, "Email owner không hợp lệ"); ok = false
      end
      ok
    end
  end
end
