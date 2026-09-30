module Customer
  class BadgesController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    def index
      @member = current_member
      Gamification.evaluate_badges(@member, current_workspace) # reflect existing history
      @badges = current_workspace.badges.ordered.to_a
      @earned = @member.member_badges.pluck(:badge_id).to_set
      @progress = @badges.index_with { |b| b.progress_for(@member) }
    end

    # One badge, with how it was (or will be) earned.
    def show
      @member = current_member
      @badge  = current_workspace.badges.find(params[:id])
      @mine   = @member.member_badges.find_by(badge_id: @badge.id)
      @done, @target = @badge.progress_for(@member)
      # "Next up" — the closest badge still locked, as the design's footer hint.
      @next_up = current_workspace.badges.ordered.to_a
                   .reject { |b| b.id == @badge.id || b.earned_by?(@member) }
                   .min_by { |b| d, t = b.progress_for(@member); t.zero? ? 1 : -(d.to_f / t) }
    end
  end
end
