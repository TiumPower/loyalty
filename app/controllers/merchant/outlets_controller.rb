module Merchant
  class OutletsController < BaseController
    include ActionView::Helpers::NumberHelper
    before_action :require_manager!, except: [:index]
    before_action :set_outlet, only: [:show, :edit, :update, :destroy, :checkin_qr]

    def index
      @q = params[:q].to_s.strip
      scope = current_workspace.outlets.order(:name)
      if @q.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where("outlets.name ILIKE :q OR outlets.code ILIKE :q OR outlets.address ILIKE :q", q: like)
      end
      @outlets = scope.to_a
      @outlet  = Outlet.new(active: true)
      load_directory_stats
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
      # Same rule as on the edit form: the button's answer is the automatic one,
      # a typed coordinate is the merchant's own and freezes the branch.
      apply_coordinate_source!
      if @outlet.save
        redirect_to merchant_outlets_path, notice: "Đã thêm chi nhánh “#{@outlet.name}”."
      else
        @outlets = current_workspace.outlets.order(:name).to_a
        load_directory_stats
        render :index, status: :unprocessable_entity
      end
    end

    def edit; end

    # "Tự lấy toạ độ": resolve whatever is in the address box right now, without
    # saving anything. The merchant looks at the answer and decides.
    #
    # Synchronous on purpose. The background job is the right shape for a save —
    # nobody should wait on Nominatim to store a branch name — but this one *is*
    # the merchant waiting for an answer, and a job they would have to poll for
    # is a worse trade than three seconds with a spinner on the button.
    def geocode
      address = params[:address].to_s.strip
      return render(json: { ok: false, error: t("merchant.outlets.geo_no_address") }) if address.blank?

      hit = GeocoderService.lookup_line(address)
      if hit.nil?
        render json: { ok: false, error: t("merchant.outlets.geo_not_found") }
      else
        render json: { ok: true, lat: hit.lat.round(7), lon: hit.lon.round(7),
                       label: hit.display_name.to_s.truncate(90),
                       note: (hit.approximate? ? t("merchant.outlets.geo_approx") : t("merchant.outlets.geo_exact")) }
      end
    rescue => e
      Rails.logger.error("[Outlets#geocode] #{e.class}: #{e.message}")
      render json: { ok: false, error: t("merchant.outlets.geo_failed") }
    end

    def update
      # Typing a coordinate claims it: the automatic lookup must not undo the
      # merchant's correction on the next address edit. Ticking "use the
      # automatic one again" hands it back.
      if params[:reset_geocode] == "1"
        @outlet.assign_attributes(geocode_manual: false, latitude: nil, longitude: nil)
      else
        apply_coordinate_source!
      end
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

    # The numbers above the directory, and the per-row staff count — one grouped
    # query each rather than a pair of counts per row.
    def load_directory_stats
      all          = current_workspace.outlets.to_a
      @total_count = all.size
      @active_count = all.count(&:active?)
      @staff_by_outlet = current_workspace.memberships.where.not(outlet_id: nil).group(:outlet_id).count
      @unassigned_staff = current_workspace.memberships.where(outlet_id: nil).count
      @today_by_outlet = Purchase.not_voided.where(created_at: Time.zone.now.all_day)
                                 .where.not(outlet_id: nil).group(:outlet_id).count
      @today_total = @today_by_outlet.values.sum
    end

    # Where the coordinates in this request came from.
    #
    # "lookup" is the "tự lấy toạ độ" button: the automatic answer, just asked
    # for by hand, so the branch stays automatic and keeps following its address.
    # Anything else that arrives changed is the keyboard, which is a correction —
    # and a correction has to survive every future address edit.
    def apply_coordinate_source!
      if params[:coords_source] == "lookup"
        @outlet.assign_attributes(geocode_manual: false, geocoded_at: Time.current)
      elsif coordinates_typed?
        @outlet.geocode_manual = true
      end
    end

    # Did this request actually change a coordinate, as opposed to posting back
    # the one the lookup already found?
    def coordinates_typed?
      p = params[:outlet] || {}
      return false if p[:latitude].blank? && p[:longitude].blank?
      # A brand new branch has nothing to compare against — and the params are
      # already assigned to it by the time this runs, so comparing would always
      # say "unchanged" and quietly lose the merchant's correction.
      return true if @outlet.new_record?
      p[:latitude].to_s != @outlet.latitude.to_s || p[:longitude].to_s != @outlet.longitude.to_s
    end

    def set_outlet
      @outlet = current_workspace.outlets.find(params[:id])
    end

    def outlet_params
      params.require(:outlet).permit(:name, :code, :address, :phone, :active,
                                     :latitude, :longitude,
                                     open_hours: [:open, :close])
    end
  end
end
