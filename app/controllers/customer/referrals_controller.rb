module Customer
  class ReferralsController < BaseController
    before_action :require_workspace!
    before_action :require_member!

    def show
      @member = current_member
      @join_url = helpers.customer_join_url(current_workspace, @member.referral_code)
      @invited   = @member.referrals_made.count
      @completed = @member.referrals_made.completed.count
      @reward_points = current_program.referral_points
      # The design lists who was actually invited — an invite screen with no
      # names on it gives the member nothing to come back for.
      @referrals = @member.referrals_made.includes(:referred).order(created_at: :desc).limit(20).to_a
    end
  end
end
