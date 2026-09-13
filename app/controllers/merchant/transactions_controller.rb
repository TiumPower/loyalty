module Merchant
  # Row-level ledger of customer point transactions for the merchant, filterable
  # by branch, date-range (day/week/month/custom), kind, and member search.
  class TransactionsController < BaseController
    include DateRangeFilterable

    PER_PAGE = 50

    def index
      @range = resolve_range
      scope  = PointTransaction.recent.includes(:member, :outlet, :staff)

      # Branch staff are locked to their outlet; owners/managers get a picker.
      if branch_scoped?
        scope = scope.where(outlet_id: scoped_outlet.id)
      else
        @branches = current_workspace.outlets.order(:name).to_a
        if params[:outlet].present? && (o = @branches.find { |x| x.id.to_s == params[:outlet].to_s })
          @outlet = o
          scope = scope.where(outlet_id: o.id)
        end
      end

      scope = in_range(scope)

      @kind = params[:kind].to_s.presence_in(PointTransaction::KINDS)
      scope = scope.where(kind: @kind) if @kind

      @q = params[:q].to_s.strip
      scope = apply_search(scope, @q)

      # Aggregates over the whole filtered set (before pagination).
      @earned  = scope.net_credits.sum(:amount)
      @spent   = scope.redemptions.sum(:amount).abs
      # Lapsed points are not redemptions (see PointTransaction#redemptions);
      # shown as their own figure so the two aren't confused.
      @expired = scope.expirations.sum(:amount).abs
      @total   = scope.count

      @page    = [params[:page].to_i, 1].max
      @transactions = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
      @has_more = @total > @page * PER_PAGE
      # The undo button needs the Purchase behind each "earn" row. :source is
      # polymorphic (can't be eager-loaded alongside a join), so look the bills up
      # in one extra query and hand the view a lookup table.
      @purchases = Purchase.where(
        id: @transactions.select { |t| t.source_type == "Purchase" }.map(&:source_id)
      ).index_by(&:id)
    end

    private

    def nav_key = :transactions

    def apply_search(scope, q)
      return scope if q.blank?
      like = "%#{q}%"
      scope.joins(:member)
           .where("members.name ILIKE :q OR members.email ILIKE :q OR members.phone ILIKE :q", q: like)
    end
  end
end
