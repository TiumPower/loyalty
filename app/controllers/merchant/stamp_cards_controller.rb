module Merchant
  class StampCardsController < BaseController
    before_action :require_manager!

    def create
      card = current_workspace.stamp_cards.new(card_params)
      if card.save
        redirect_to merchant_gamification_path, notice: "Đã tạo thẻ tem “#{card.title}”."
      else
        redirect_to merchant_gamification_path, alert: card.errors.full_messages.to_sentence
      end
    end

    def update
      card = current_workspace.stamp_cards.find(params[:id])
      if card.update(card_params)
        redirect_to merchant_gamification_path, notice: "Đã cập nhật thẻ tem “#{card.title}”."
      else
        redirect_to merchant_gamification_path, alert: card.errors.full_messages.to_sentence
      end
    end

    # Pause / resume without touching the rest of the card. Answers JSON for the
    # inline button; a non-JS client still gets the page back with a notice.
    def toggle
      card = current_workspace.stamp_cards.find(params[:id])
      card.update_columns(active: !card.active?, updated_at: Time.current)
      notice = card.active? ? t("merchant.gami.stamp_resumed", title: card.title)
                            : t("merchant.gami.stamp_suspended", title: card.title)
      respond_to do |format|
        format.json { render json: { ok: true, active: card.active?, notice: notice } }
        format.html { redirect_to merchant_gamification_path, notice: notice }
      end
    end

    # Deleting a stamp card cascades to its memberships (dependent: :destroy),
    # which would wipe every customer's in-progress stamps. To avoid silently
    # erasing customer progress, only hard-delete a card nobody is collecting;
    # if any customer has stamps or a completed cycle, archive it (active: false)
    # instead — their progress and any earned vouchers stay intact.
    def destroy
      card = current_workspace.stamp_cards.find(params[:id])
      in_progress = card.stamp_card_memberships.where("count > 0 OR completed_count > 0").count
      if in_progress.positive?
        card.update(active: false)
        redirect_to merchant_gamification_path, notice: t("merchant.gami.stamp_archived", n: in_progress)
      else
        card.destroy
        redirect_to merchant_gamification_path, notice: t("merchant.gami.stamp_deleted")
      end
    end

    private

    def nav_key = :gamification

    def card_params
      params.require(:stamp_card).permit(:title, :description, :icon, :target_count, :reward_id, :active)
    end
  end
end
