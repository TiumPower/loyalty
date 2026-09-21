module Merchant
  class MissionsController < BaseController
    before_action :require_manager!

    def create
      # A social_share mission is split into ONE mission per selected network, so
      # the customer sees a distinct task per platform (each with its own points,
      # submission and completion tick).
      return create_social_share_missions if params.dig(:mission, :mission_type) == "social_share"

      mission = current_workspace.missions.new(mission_params)
      mission.proof_config = build_proof_config if mission.photo_proof?
      if mission.save
        redirect_to merchant_gamification_path, notice: "Đã tạo nhiệm vụ “#{mission.title}”."
      else
        redirect_to merchant_gamification_path, alert: mission.errors.full_messages.to_sentence
      end
    end

    def update
      mission = current_workspace.missions.find(params[:id])
      mission.assign_attributes(mission_params)
      mission.proof_config = mission.photo_proof? ? build_proof_config : {}
      if mission.save
        redirect_to merchant_gamification_path, notice: "Đã cập nhật nhiệm vụ “#{mission.title}”."
      else
        redirect_to merchant_gamification_path, alert: mission.errors.full_messages.to_sentence
      end
    end

    # Pause / resume without saving the rest of the mission. JSON for the inline
    # button, HTML redirect for a client without JS.
    def toggle
      mission = current_workspace.missions.find(params[:id])
      mission.update_columns(active: !mission.active?, updated_at: Time.current)
      notice = mission.active? ? t("merchant.gami.mission_resumed", title: mission.title)
                               : t("merchant.gami.mission_suspended", title: mission.title)
      respond_to do |format|
        format.json { render json: { ok: true, active: mission.active?, notice: notice } }
        format.html { redirect_to merchant_gamification_path, notice: notice }
      end
    end

    def destroy
      current_workspace.missions.find(params[:id]).destroy
      redirect_to merchant_gamification_path, notice: "Đã xoá nhiệm vụ."
    end

    private

    def nav_key = :gamification

    # Create one social_share mission per ticked network. Title/icon are set from
    # the network; points fall back to the flat reward when a per-network value
    # isn't given.
    def create_social_share_missions
      enabled = (params.dig(:mission, :proof_config, :enabled) || {}).to_unsafe_h
      pts_in  = (params.dig(:mission, :proof_config, :platforms) || {}).to_unsafe_h
      plats   = Mission::PROOF_PLATFORMS.select { |p| enabled[p].present? }
      if plats.empty?
        return redirect_to merchant_gamification_path, alert: "Hãy chọn ít nhất một mạng xã hội."
      end
      base_pts = params.dig(:mission, :reward_points).to_i
      loc      = current_workspace.locale_default.presence || I18n.locale
      created  = 0
      plats.each do |plat|
        pts = pts_in[plat].to_i.positive? ? pts_in[plat].to_i : base_pts
        mission = current_workspace.missions.new(
          mission_type: "social_share", period: "once", goal: 1, active: true,
          reward_points: pts,
          title: I18n.t("merchant.gami.share_task_title", platform: Mission::PLATFORM_LABELS[plat], locale: loc),
          icon:  Mission::PLATFORM_ICONS[plat],
          proof_config: { "platform" => plat, "platforms" => { plat => pts_in[plat].to_i } }
        )
        created += 1 if mission.save
      end
      redirect_to merchant_gamification_path,
                  notice: "Đã tạo #{created} nhiệm vụ chia sẻ mạng xã hội."
    end

    def mission_params
      params.require(:mission).permit(:title, :icon, :mission_type, :period, :goal, :reward_points, :active)
    end

    # social_share config: the merchant ticks which networks are allowed
    # (mission[proof_config][enabled][facebook]=1) and may set per-platform points
    # (mission[proof_config][platforms][facebook]=50; blank/0 = default reward).
    # Only ticked platforms are stored; their keys are the customer's allowlist.
    def build_proof_config
      enabled  = (params.dig(:mission, :proof_config, :enabled) || {}).to_unsafe_h
      pts_in   = (params.dig(:mission, :proof_config, :platforms) || {}).to_unsafe_h
      platforms = Mission::PROOF_PLATFORMS.filter_map do |plat|
        next unless enabled[plat].present?
        [plat, pts_in[plat].to_i]
      end.to_h
      platforms.present? ? { "platforms" => platforms } : {}
    end
  end
end
