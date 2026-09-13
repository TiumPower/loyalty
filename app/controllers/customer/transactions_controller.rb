module Customer
  class TransactionsController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    PER = 30

    def index
      @member = current_member
      @page = [params[:page].to_i, 1].max
      # Every row read its branch off its own association, so a full page cost
      # thirty queries on top of the page.
      @transactions = @member.point_transactions.recent.includes(:outlet)
                             .limit(PER).offset((@page - 1) * PER).to_a
      @has_more = @member.point_transactions.count > @page * PER
      # "Tích điểm từ hoá đơn" with no bill on it left the customer no way to
      # check the shop's arithmetic — the one thing this screen is for. :source
      # is polymorphic and can't be eager-loaded alongside the join, so look the
      # bills up in one extra query (same as the merchant ledger does).
      @purchases = Purchase.where(
        id: @transactions.select { |t| t.source_type == "Purchase" }.map(&:source_id)
      ).index_by(&:id)
    end
  end
end
