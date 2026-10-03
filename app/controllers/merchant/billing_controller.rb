module Merchant
  class BillingController < BaseController
    def show
      @workspace = current_workspace
      @plan = current_workspace.plan_record
      @members = Member.count
      @plans = Plan.ordered.to_a
      @invoices = current_workspace.invoices.recent.limit(12).to_a
      @next_start, @next_end = current_workspace.next_billing_period
      @payos_ready = PayosService.new.configured?
      # What the shop is actually using against what the plan allows. A limit of
      # nil means unlimited, which has no bar to draw.
      @usage = [
        { key: :members, used: @members,                          cap: @plan.max_members },
        { key: :outlets, used: current_workspace.outlets.count,   cap: @plan.max_outlets },
        { key: :staff,   used: current_workspace.memberships.count, cap: nil },
      ]
      # Đọc thẳng danh sách tính năng mà gói thật sự quyết định, thay vì dò các
      # cột `allow_*` — dò cột là cách "Thử nghiệm A/B" lọt lên trang này dù
      # chưa ai viết tính năng đó.
      @flags = Workspace::PLAN_FEATURES.map { |f| [f.to_s, @plan.public_send("allow_#{f}")] }
    end

    private

    def nav_key = :billing
  end
end
