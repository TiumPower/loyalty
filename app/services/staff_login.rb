# Self-login QR for merchant staff: a short-lived signed token that logs the
# SAME user back in on their phone (no password typing at the counter). Token is
# scoped to the user + workspace and expires quickly; the profile QR rotates.
module StaffLogin
  TTL = 2.minutes

  def self.verifier
    Rails.application.message_verifier("loyalty/staff_login")
  end

  def self.encode(user, workspace)
    verifier.generate({ "u" => user.id, "w" => workspace.id, "n" => SecureRandom.hex(4) },
                      expires_in: TTL)
  end

  # Returns the User if the token is valid, unexpired, and the user still has a
  # membership in the encoded workspace; else nil.
  def self.resolve(token)
    data = verifier.verify(token.to_s.strip)
    return nil unless data.is_a?(Hash)
    user = User.find_by(id: data["u"])
    ws   = Workspace.find_by(id: data["w"])
    return nil unless user && ws && user.memberships.exists?(workspace_id: ws.id)
    [ user, ws ]
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil # expired tokens also raise InvalidSignature in Rails 7.2
  end
end
