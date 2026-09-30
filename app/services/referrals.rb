# Referral lifecycle (top-level — see EarnPoints note on the Loyalty namespace).
module Referrals
  module_function

  # A new member joined via a referrer's code — create a pending referral.
  def attach(referred:, referrer_code:)
    return if referrer_code.blank? || referred.referred_by_id.present?
    referrer = Member.find_by(referral_code: referrer_code.to_s.upcase)
    return if referrer.nil? || referrer.id == referred.id

    referred.update!(referred_by: referrer)
    Referral.find_or_create_by!(referred: referred) do |r|
      r.workspace = referred.workspace
      r.referrer = referrer
      r.state = "pending"
    end
  end

  # Called after a member's purchase: if they were referred and this is their
  # first purchase, complete the referral and reward BOTH sides.
  def on_purchase(member)
    program = member.workspace.program
    return unless program.referral_enabled
    referral = Referral.pending.find_by(referred_id: member.id)
    return unless referral
    return if member.purchases.not_voided.count > 1 # only on the first

    pts = program.referral_points
    Referral.transaction do
      award(referral.referrer, pts, I18n.t("customer.notices.referral_note_referrer"))
      award(referral.referred, pts, I18n.t("customer.notices.referral_note_referred"))
      referral.update!(state: "completed", reward_points: pts, completed_at: Time.current)
      advance_refer_missions(referral.referrer)
    end
    # Both sides were paid in silence: the referrer saw a number change on a
    # screen they had no reason to open. The design puts it in the inbox
    # ("Friend joined!"), which is also the only place the invitee learns why
    # they started with points.
    announce(referral, pts)
  rescue => e
    Rails.logger.error("[Referrals] #{e.class}: #{e.message}")
  end

  def announce(referral, points)
    shop = referral.workspace.name
    MemberNotifier.notify(referral.referrer, "referral_joined", icon: "🤝", link: "/refer",
                          name: referral.referred&.display_name, shop: shop, n: points)
    MemberNotifier.notify(referral.referred, "referral_welcome", icon: "🤝", link: "/history",
                          name: referral.referrer&.display_name, n: points)
  end

  def award(member, points, note)
    PointTransaction.create!(workspace: member.workspace, member: member, kind: "referral",
                             amount: points, note: note)
    member.recompute_points!
  end

  # Advance the referrer's "refer" missions (+1 per completed referral) and award
  # their reward points when the goal is reached.
  def advance_refer_missions(referrer)
    ws = referrer.workspace
    return unless ws.program.gamification_enabled
    ws.missions.active.where(mission_type: "refer").each do |mission|
      mp = mission.progress_for(referrer)
      mp.save! if mp.new_record?
      mp.advance!(1) unless mp.completed?
    end
  end
end
