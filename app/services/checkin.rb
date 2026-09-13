# Store check-in: a member proves they're on-site by scanning the merchant's
# printed check-in QR. The QR carries a signed, non-expiring workspace token
# (static poster). One check-in per member per day completes any active
# "checkin" missions and awards their points.
module Checkin
  module_function

  def verifier
    Rails.application.message_verifier("loyalty/checkin")
  end

  # Static token (no expiry) so a printed poster keeps working — until the
  # merchant rotates the nonce. Optionally scoped to a branch so check-ins are
  # attributed to the outlet whose QR was scanned.
  def encode(workspace, outlet = nil)
    verifier.generate({ "w" => workspace.id, "o" => outlet&.id, "n" => workspace.checkin_nonce })
  end

  # Returns [valid?, outlet_id] — valid only for this workspace AND current nonce.
  def decode(token, workspace:)
    data = verifier.verify(token.to_s.strip)
    ok = data.is_a?(Hash) && data["w"].to_i == workspace.id && data["n"].to_s == workspace.checkin_nonce.to_s
    [ok, (ok ? data["o"] : nil)]
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    [false, nil]
  end

  # Complete today's check-in for the member. Returns [status, points_awarded]:
  #   :none    — workspace has no active check-in mission
  #   :already — the member already checked in today
  #   :done    — checked in (missions advanced, points awarded)
  # "Already checked in today" was read off whatever copy of the member the
  # caller happened to hold and written a few statements later, with nothing in
  # between. Two taps on the QR — the normal case on a phone with a slow
  # connection — both got past it, and the second one showed the customer a
  # success screen reading "+0 điểm". Re-read the flag under a row lock so one
  # scan means one check-in.
  def check_in!(member, workspace, outlet = nil)
    missions = workspace.missions.active.where(mission_type: "checkin").to_a
    return [:none, 0] if missions.empty?

    points = 0
    status = nil
    Member.transaction do
      locked = Member.lock.find(member.id)
      if locked.last_checkin_at&.to_date == Date.current
        status = :already
        raise ActiveRecord::Rollback
      end
      locked.update!(last_checkin_at: Time.current)
      missions.each do |m|
        mp = m.progress_for(locked)
        mp.save! if mp.new_record?
        next if mp.completed?
        mp.advance!(1, outlet: outlet)
        points += m.reward_points if mp.completed?
      end
      status = :done
    end

    member.reload
    status == :done ? [:done, points] : [:already, 0]
  end
end
