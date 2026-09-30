module Merchant
  class ScannerController < BaseController
    # Minimal staff-mobile landing after a quick-login QR scan: just the shop's
    # logo/name + one button into the counter scanner (earn / redeem). No sidebar.
    def launcher
      # Show the "Shop QR" home button only when the user has a branch to display.
      @has_checkin_qr = checkin_qr_outlets.any?
      # Owner/manager can set which branch this phone rings up for, same as the
      # desk view — an unset branch misattributes every bill taken here.
      if params[:outlet].present? && selectable_outlets.any? { |o| o.id.to_s == params[:outlet].to_s }
        session[:active_outlet_id] = params[:outlet]
        # current_outlet memoises, and selectable_outlets above may have warmed it.
        remove_instance_variable(:@current_outlet) if instance_variable_defined?(:@current_outlet)
      end
      # The same counter figures the desk view shows, so a cashier can see their
      # own shift without opening the scanner first.
      load_counter_activity
      render layout: "launcher"
    end

    def show
      @tab = %w[earn redeem pos].include?(params[:tab]) ? params[:tab] : "earn"
      # Owner/manager can switch the active branch for this session.
      if params[:outlet].present? && selectable_outlets.any? { |o| o.id.to_s == params[:outlet].to_s }
        session[:active_outlet_id] = params[:outlet]
      end
      # Kiosk mode = the standalone mobile counter scanner opened from the
      # staff quick-login launcher: same tool, but a minimal chrome (no merchant
      # sidebar/menu) so a phone at the counter behaves like a dedicated device.
      @kiosk = params[:kiosk].present?
      # What this counter has done today — the design keeps it beside the tool so
      # a cashier can see their own work without leaving the screen. Kiosk mode
      # stays a single column, so it does not need this.
      load_counter_activity unless @kiosk
      render layout: "scanner_kiosk" if @kiosk
    end

    # Standalone branch check-in QR screen — a peer of the scanner on the staff
    # home. Owner may pick any branch; a manager/staff sees only their own.
    def checkin_qr
      @qr_outlets = checkin_qr_outlets
      @qr_outlet  = @qr_outlets.find { |o| o.id.to_s == params[:qr_outlet].to_s } || @qr_outlets.first
      render layout: "scanner_kiosk"
    end

    private

    def nav_key = :scanner

    # Today's postings at the active branch (all branches when none is chosen).
    def load_counter_activity
      scope = PointTransaction.where(created_at: Time.zone.now.all_day)
      scope = scope.where(outlet_id: current_outlet.id) if current_outlet
      @today_earned  = scope.net_credits.sum(:amount)
      @today_spent   = scope.redemptions.sum(:amount).abs
      @today_count   = scope.count
      @today_recent  = scope.recent.includes(:member).limit(5).to_a
    end

    # Branches whose check-in QR the current user may display.
    #   owner            → every branch (can pick)
    #   manager / staff  → only the branch they belong to
    def checkin_qr_outlets
      m = current_membership
      return current_workspace.outlets.order(:name).to_a if m&.owner?
      [m&.outlet].compact
    end
  end
end
