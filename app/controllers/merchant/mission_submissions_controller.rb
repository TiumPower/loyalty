module Merchant
  # Manual review queue for photo-proof missions (Google review / social share).
  # AI auto-verification (Phase B) pre-decides many of these; anything left
  # pending (or that AI was unsure about) lands here for a human decision.
  class MissionSubmissionsController < BaseController
    before_action :require_manager!
    before_action :set_submission, only: [:approve, :reject]

    def index
      scope = MissionProgress.where(mission_id: photo_mission_ids)
      @status = params[:status].to_s.presence_in(MissionProgress::APPROVAL_STATUSES) || "pending"
      scope = scope.where(approval_status: @status)
      @submissions = scope.includes(:member, :mission, photo_attachment: :blob)
                          .order(submitted_at: :desc).to_a
      @pending_count = MissionProgress.where(mission_id: photo_mission_ids, approval_status: "pending").count
    end

    def approve
      @submission.approve!(reviewer: current_user)
      redirect_to merchant_mission_submissions_path, notice: "Đã duyệt minh chứng."
    end

    def reject
      @submission.reject!(reviewer: current_user, reason: params[:reason])
      redirect_to merchant_mission_submissions_path, notice: "Đã từ chối minh chứng."
    end

    private

    def nav_key = :missions_setup

    def photo_mission_ids
      current_workspace.missions.where(mission_type: Mission::PHOTO_PROOF_TYPES).select(:id)
    end

    def set_submission
      @submission = MissionProgress.where(mission_id: photo_mission_ids).find(params[:id])
    end
  end
end
