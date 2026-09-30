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
      # The feature switches that live on the plan row, so this list cannot drift
      # from what the code actually checks.
      @flags = %w[stamps gamification campaigns custom_domain ab_testing]
               .select { |f| @plan.respond_to?("allow_#{f}") }
               .map { |f| [f, @plan.public_send("allow_#{f}")] }
    end

    private

    def nav_key = :billing
  end
end
