module Customer
  class PushController < BaseController
    before_action :require_workspace!
    before_action :require_member!
    skip_before_action :verify_authenticity_token, only: [ :subscribe, :unsubscribe ], raise: false

    # Store a browser PushSubscription for the current member.
    def subscribe
      sub = params.permit(:endpoint, keys: [ :p256dh, :auth ])
      endpoint = sub[:endpoint]
      keys = sub[:keys] || {}
      if endpoint.blank? || keys[:p256dh].blank? || keys[:auth].blank?
        return render json: { ok: false }, status: :unprocessable_entity
      end
      PushSubscription.store!(member: current_member, endpoint: endpoint,
                              p256dh: keys[:p256dh], auth: keys[:auth])
      render json: { ok: true }
    end

    def unsubscribe
      current_member.push_subscriptions.where(endpoint: params[:endpoint]).destroy_all if params[:endpoint].present?
      render json: { ok: true }
    end
  end
end
