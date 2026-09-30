module Merchant
  class ScannerController < BaseController
    # Minimal staff-mobile landing after a quick-login QR scan: just the shop's
    # logo/name + one button into the counter scanner (earn / redeem). No sidebar.
    def launcher
      # Show the "Shop QR" home button only when the user has a branch to display.
      @has_checkin_qr = checkin_qr_outlets.any?
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

    # Branches whose check-in QR the current user may display.
    #   owner            → every branch (can pick)
    #   manager / staff  → only the branch they belong to
    def checkin_qr_outlets
      m = current_membership
      return current_workspace.outlets.order(:name).to_a if m&.owner?
      [ m&.outlet ].compact
    end
  end
end
