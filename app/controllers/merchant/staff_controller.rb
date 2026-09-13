module Merchant
  class StaffController < BaseController
    before_action :require_manager!, except: [:index]

    def index
      @memberships = current_workspace.memberships.includes(:user, :outlet).to_a
      @outlets = current_workspace.outlets.order(:name).to_a
    end

    # Invite a staff member by email (creates the user if new + a membership).
    def create
      email = params[:email].to_s.downcase.strip
      name  = params[:name].presence || email.split("@").first
      role  = Membership::ROLES.include?(params[:role]) ? params[:role] : "staff"

      if email.blank?
        return redirect_to merchant_staff_index_path, alert: "Vui lòng nhập email."
      end

      user = User.find_or_initialize_by(email: email)
      new_user = user.new_record?
      if new_user
        user.assign_attributes(name: name, password: SecureRandom.hex(16), locale: "vi")
        user.save!
      end
      if current_workspace.memberships.exists?(user_id: user.id)
        return redirect_to merchant_staff_index_path, alert: "Nhân viên này đã có trong workspace."
      end
      current_workspace.memberships.create!(user: user, role: role, outlet_id: params[:outlet_id].presence)

      notice =
        if new_user && EmailOtp.configured?
          token = user.send(:set_reset_password_token)
          StaffMailer.invite(user, current_workspace, token).deliver_later
          "Đã mời #{name} — email đặt mật khẩu đã gửi tới #{email}."
        elsif new_user
          "Đã thêm #{name}. Chưa cấu hình email: nhân viên vào /merchant/login → “Quên mật khẩu” để đặt mật khẩu."
        else
          "Đã thêm #{name} vào cửa hàng (dùng mật khẩu tài khoản sẵn có)."
        end
      redirect_to merchant_staff_index_path, notice: notice
    end

    def update
      m = current_workspace.memberships.find(params[:id])
      return redirect_to(merchant_staff_index_path, alert: "Vai trò không hợp lệ.") unless Membership::ROLES.include?(params[:role])
      # #destroy already refuses to remove the last owner; demoting them reaches
      # the same dead end by another door. With no owner or manager left, nobody
      # can open this page to undo it — the shop is locked out of its own
      # settings, billing and staff for good.
      if m.owner? && params[:role] != "owner" && last_owner?(m)
        return redirect_to merchant_staff_index_path,
          alert: "Không thể đổi vai trò của chủ cửa hàng duy nhất — hãy chỉ định một chủ khác trước."
      end
      m.update(role: params[:role], outlet_id: params[:outlet_id].presence)
      redirect_to merchant_staff_index_path, notice: "Đã cập nhật phân quyền."
    end

    def destroy
      m = current_workspace.memberships.find(params[:id])
      if m.owner? && last_owner?(m)
        redirect_to merchant_staff_index_path, alert: "Không thể xoá chủ cửa hàng duy nhất."
      else
        m.destroy
        redirect_to merchant_staff_index_path, notice: "Đã gỡ nhân viên."
      end
    end

    private

    def last_owner?(membership)
      current_workspace.memberships.where(role: "owner").where.not(id: membership.id).none?
    end

    def nav_key = :staff
  end
end
