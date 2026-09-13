module Merchant
  class OutletsController < BaseController
    include ActionView::Helpers::NumberHelper
    before_action :require_manager!, except: [:index]
    before_action :set_outlet, only: [:show, :edit, :update, :destroy, :checkin_qr]

    def index
      @outlets = current_workspace.outlets.order(:name)
      @outlet  = Outlet.new(active: true)
    end

    # Branch detail: this outlet's performance, staff and recent activity.
    def show
      oid = @outlet.id
      @revenue   = Purchase.not_voided.where(outlet_id: oid).sum(:amount)
      @points    = Purchase.not_voided.where(outlet_id: oid).sum(:points_earned)
      @purchases = Purchase.not_voided.where(outlet_id: oid).count
      @customers = Purchase.not_voided.where(outlet_id: oid).distinct.count(:member_id)
      @vouchers  = Voucher.where(used_outlet_id: oid, state: "used").count
      @recent    = PointTransaction.where(outlet_id: oid).includes(:member).order(created_at: :desc).limit(15).to_a
      @staff     = current_workspace.memberships.where(outlet_id: oid).includes(:user).to_a
      # Every branch always has a check-in QR (independent of whether a check-in
      # mission exists — the QR is the branch's identity for check-in/earn).
      @checkin_url = helpers.customer_scan_url(current_workspace, checkin: Checkin.encode(current_workspace, @outlet))
    end

    # Printable per-branch check-in QR (attributes check-ins to this outlet).
    def checkin_qr
      url = helpers.customer_scan_url(current_workspace, checkin: Checkin.encode(current_workspace, @outlet))
      send_data helpers.qr_png(url, size: 720), type: "image/png",
                disposition: "attachment", filename: "checkin-#{@outlet.name.parameterize.presence || @outlet.id}.png"
    end

    def create
      unless current_workspace.can_add_outlet?
        return redirect_to merchant_outlets_path,
          alert: "Gói #{current_workspace.plan_record.name} chỉ cho phép #{current_workspace.outlet_limit} chi nhánh. Nâng cấp gói để thêm."
      end
      @outlet = current_workspace.outlets.new(outlet_params)
      if @outlet.save
        redirect_to merchant_outlets_path, notice: "Đã thêm chi nhánh “#{@outlet.name}”."
      else
        @outlets = current_workspace.outlets.order(:name)
        render :index, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @outlet.update(outlet_params)
        redirect_to merchant_outlets_path, notice: "Đã cập nhật chi nhánh."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      unless @outlet.destroyable?
        return redirect_to merchant_outlets_path,
          alert: "Chi nhánh “#{@outlet.name}” đã có #{number_with_delimiter(@outlet.history_count)} giao dịch nên không xoá được — " \
                 "hãy tắt hoạt động để ẩn khỏi máy quét mà vẫn giữ lịch sử."
      end
      @outlet.destroy
      redirect_to merchant_outlets_path, notice: "Đã xoá chi nhánh."
    rescue ActiveRecord::InvalidForeignKey
      # Belt and braces: anything else still pointing at the branch.
      redirect_to merchant_outlets_path,
        alert: "Không xoá được chi nhánh này vì đang có dữ liệu liên quan. Hãy tắt hoạt động thay vì xoá."
    end

    private

    def nav_key = :outlets

    def set_outlet
      @outlet = current_workspace.outlets.find(params[:id])
    end

    def outlet_params
      params.require(:outlet).permit(:name, :code, :address, :phone, :active)
    end
  end
end
