# Delivers scheduled broadcasts whose time has arrived. Runs every 5 minutes.
class BroadcastDeliveryJob < ApplicationJob
  queue_as :default

  def perform
    ActsAsTenant.without_tenant do
      Broadcast.due.includes(:workspace).find_each do |b|
        # Claim it before doing any work — see Broadcast#claim_for_delivery!.
        next unless b.claim_for_delivery!
        ActsAsTenant.with_tenant(b.workspace) { b.deliver_to_segment! }
      rescue => e
        Rails.logger.error("[BroadcastDelivery] ##{b.id}: #{e.class} #{e.message}")
      end
    end
  end
end
