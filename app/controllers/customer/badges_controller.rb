module Customer
  class BadgesController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    def index
      @member = current_member
      Gamification.evaluate_badges(@member, current_workspace) # reflect existing history
      @badges = current_workspace.badges.ordered.to_a
      @earned = @member.member_badges.pluck(:badge_id).to_set
      @progress = Badge.progress_map(@badges, @member)
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
      @journey = outlet_journey
    end

    private

    # "Your outlet journey" from the design: the branches this member has been
    # to, in the order they first visited them. Only for badges earned by going
    # somewhere — against a points total it would just be noise. Keys are
    # Badge#criteria_type.
    JOURNEY_TYPES = %w[first_purchase purchases_count night_owl].freeze

    def outlet_journey
      return [] unless JOURNEY_TYPES.include?(@badge.criteria_type.to_s)
      firsts = Purchase.not_voided.where(member_id: @member.id).where.not(outlet_id: nil)
                       .group(:outlet_id).minimum(:created_at)
      return [] if firsts.empty?
      outlets = current_workspace.outlets.where(id: firsts.keys).index_by(&:id)
      firsts.sort_by { |_, at| at }
            .filter_map { |id, at| [outlets[id], at] if outlets[id] }
    end
  end
end
