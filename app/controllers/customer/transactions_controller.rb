module Customer
  class TransactionsController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    PER = 30

    def index
      @member = current_member
      @page = [params[:page].to_i, 1].max
      # Earned / redeemed is a filter on the ledger, not a client-side hide:
      # the list is paginated, so hiding rows in the browser would leave a page
      # of thirty showing three.
      @filter = %w[earned redeemed].include?(params[:filter]) ? params[:filter] : "all"
      scope = case @filter
              when "earned"   then @member.point_transactions.where("amount > 0")
              when "redeemed" then @member.point_transactions.where("amount < 0")
              else                 @member.point_transactions
              end
      # Every row read its branch off its own association, so a full page cost
      # thirty queries on top of the page.
      @transactions = scope.recent.includes(:outlet)
                           .limit(PER).offset((@page - 1) * PER).to_a
      @has_more = scope.count > @page * PER
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
