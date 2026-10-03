# Fold one member profile into another.
#
# Phone login matches on (workspace, phone), so a customer who used to sign in
# by email and now signs in by phone can end up with two profiles — points on
# one, stamps on the other. This is how a shop owner puts them back together.
#
# Two rules shape everything here:
#
#   1. Move the rows FIRST, destroy the loser LAST. Several of Member's
#      associations are `dependent: :destroy`, so destroying first would delete
#      the very history we are trying to preserve.
#   2. Six tables carry a UNIQUE index that includes member_id. A plain
#      `update_all(member_id:)` raises on every one of them the moment both
#      profiles hold the same badge / mission period / promo claim / push
#      endpoint / stamp card, so each is reassigned row by row with an explicit
#      rule for the collision.
class MemberMerge
  Result = Struct.new(:ok, :error, :moved, keyword_init: true) do
    def ok? = !!ok
  end

  def self.call(keeper:, loser:, actor: nil) = new(keeper: keeper, loser: loser, actor: actor).call

  # What a merge would move, counted without touching anything. Shown on the
  # confirmation screen: an owner should never have to take our word for what
  # an irreversible operation is about to do.
  def self.preview(keeper:, loser:)
    return {} if keeper.nil? || loser.nil?
    {
      "điểm giao dịch"   => PointTransaction.unscoped.where(member_id: loser.id).count,
      "hoá đơn"          => Purchase.unscoped.where(member_id: loser.id).count,
      "voucher"          => Voucher.unscoped.where(member_id: loser.id).count,
      "thẻ tem"          => StampCardMembership.unscoped.where(member_id: loser.id).count,
      "huy hiệu"         => MemberBadge.unscoped.where(member_id: loser.id).count,
      "nhiệm vụ"         => MissionProgress.unscoped.where(member_id: loser.id).count,
      "đánh giá"         => Rating.unscoped.where(member_id: loser.id).count,
      "thông báo"        => Notification.unscoped.where(member_id: loser.id).count,
      "người được mời"   => Member.unscoped.where(referred_by_id: loser.id).count
    }.reject { |_, count| count.zero? }
  end

  def initialize(keeper:, loser:, actor: nil)
    @keeper = keeper
    @loser  = loser
    @actor  = actor
    @moved  = Hash.new(0)
  end

  def call
    return failure("Thiếu hồ sơ để gộp.")            if @keeper.nil? || @loser.nil?
    return failure("Không thể gộp một hồ sơ với chính nó.") if @keeper.id == @loser.id
    return failure("Hai hồ sơ không cùng một cửa hàng.")    if @keeper.workspace_id != @loser.workspace_id

    ActiveRecord::Base.transaction do
      lock_both!
      move_history!
      move_unique_rows!
      move_referrals!
      move_avatar!
      absorbed = absorb_profile!
      @loser.reload.destroy!
      finish!(absorbed)
    end
    Result.new(ok: true, moved: @moved)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::RecordNotDestroyed => e
    Rails.logger.error("[MemberMerge] #{@loser&.id} → #{@keeper&.id} failed: #{e.class}: #{e.message}")
    failure(e.message)
  end

  private

  def failure(message) = Result.new(ok: false, error: message, moved: {})

  # Locked in id order so two operators merging overlapping pairs queue up
  # instead of deadlocking.
  def lock_both!
    [@keeper, @loser].sort_by(&:id).each(&:lock!)
  end

  # Tables where a member can hold any number of rows: a bulk reassign is both
  # correct and the only sane thing for a points ledger.
  PLAIN = [
    ["PointTransaction", :member_id],
    ["Purchase",         :member_id],
    ["Voucher",          :member_id],
    ["Notification",     :member_id],
    ["SpinLog",          :member_id],
    ["Rating",           :member_id],
    ["PosCharge",        :member_id]
  ].freeze

  def move_history!
    PLAIN.each do |class_name, fk|
      model = class_name.safe_constantize or next
      @moved[model.table_name] += model.unscoped.where(fk => @loser.id)
                                       .update_all(fk => @keeper.id, updated_at: Time.current)
    end
  end

  def move_unique_rows!
    # One badge is one badge; the earlier award is the true one.
    move_unique!(MemberBadge, [:badge_id])

    # Same device subscribed under both profiles — one subscription is enough.
    move_unique!(PushSubscription, [:endpoint])

    # A promo code is claimable once per person, and they are one person.
    move_unique!(PromoClaim, [:promo_code_id])

    # Same mission in the same period: the work was done once by one customer,
    # so the progress adds up and the earlier completion stands.
    move_unique!(MissionProgress, [:mission_id, :period_key]) do |mine, theirs|
      mine.progress     += theirs.progress
      mine.completed_at = [mine.completed_at, theirs.completed_at].compact.min
      mine.claimed_at ||= theirs.claimed_at
      mine.save!(validate: false)
    end

    # Stamps collected on two cards for the same shop belong on one card.
    move_unique!(StampCardMembership, [:stamp_card_id]) do |mine, theirs|
      mine.count           += theirs.count
      mine.completed_count += theirs.completed_count
      mine.last_stamp_at   = [mine.last_stamp_at, theirs.last_stamp_at].compact.max
      mine.save!(validate: false)
    end
  end

  # Reassign row by row, because `unique_on` + member_id is a unique index.
  # Without a block the loser's colliding row is dropped; with one, the block
  # folds its values into the keeper's row first.
  def move_unique!(model, unique_on, fk: :member_id)
    held = model.unscoped.where(fk => @keeper.id).pluck(*unique_on).map { |v| Array(v) }.to_set

    model.unscoped.where(fk => @loser.id).find_each do |row|
      key = unique_on.map { |column| row[column] }
      if held.include?(key)
        if block_given?
          mine = model.unscoped.find_by(unique_on.zip(key).to_h.merge(fk => @keeper.id))
          yield(mine, row) if mine
        end
        row.destroy!
        @moved["#{model.table_name}_merged"] += 1
      else
        row.update_columns(fk => @keeper.id)
        held << key
        @moved[model.table_name] += 1
      end
    end
  end

  def move_referrals!
    return unless defined?(Referral)

    # People the loser referred were referred by the same human. The keeper is
    # excluded: if IT was referred by the loser, repointing would make the
    # survivor its own referrer — a state that is impossible in normal use and
    # only becomes representable mid-merge.
    @moved["referrals_made"] += Referral.unscoped.where(referrer_id: @loser.id)
                                        .update_all(referrer_id: @keeper.id, updated_at: Time.current)
    Member.unscoped.where(referred_by_id: @loser.id).where.not(id: @keeper.id)
          .update_all(referred_by_id: @keeper.id)
    @keeper.update_columns(referred_by_id: nil) if @keeper.referred_by_id == @loser.id

    # referrals.referred_id is UNIQUE — one person can only have been referred
    # once, so the keeper's own record wins and the loser's is dropped.
    theirs = Referral.unscoped.find_by(referred_id: @loser.id)
    return if theirs.nil?

    if Referral.unscoped.exists?(referred_id: @keeper.id)
      theirs.destroy!
      @moved["referrals_received_merged"] += 1
    else
      theirs.update_columns(referred_id: @keeper.id)
      @moved["referrals_received"] += 1
    end
  end

  def move_avatar!
    return unless @loser.avatar.attached?
    return if @keeper.avatar.attached?
    @keeper.avatar.attach(@loser.avatar.blob)
    @moved["avatar"] += 1
  end

  # The surviving profile takes anything it was missing. Returns what the loser
  # carried, for the audit trail: `phone` and `email` are unique per workspace,
  # so whatever the keeper cannot adopt is about to be destroyed with the row.
  def absorb_profile!
    snapshot = @loser.slice(:id, :name, :phone, :email, :birthday, :gender, :join_source)

    @keeper.name       = @loser.name       if @keeper.name.blank?
    @keeper.birthday ||= @loser.birthday
    @keeper.gender   ||= @loser.gender
    @keeper.save! if @keeper.changed?

    snapshot
  end

  # Both identifiers are unique per workspace, so the keeper can only take them
  # once the loser's row is gone.
  def finish!(absorbed)
    @keeper.phone = absorbed["phone"] if @keeper.phone.blank? && absorbed["phone"].present?
    @keeper.email = absorbed["email"] if @keeper.email.blank? && absorbed["email"].present?

    # A merge can push the survivor over a tier line as an accounting artefact;
    # it is not a promotion they earned, so it is not announced.
    @keeper.save! if @keeper.changed?
    @keeper.recompute_points_quietly!

    trace = (@keeper.settings["merged_from"] ||= [])
    trace << absorbed.merge("at" => Time.current.iso8601, "by" => @actor&.email, "moved" => @moved)
    @keeper.update_column(:settings, @keeper.settings)

    Rails.logger.info("[MemberMerge] #{absorbed['id']} → #{@keeper.id} #{@moved.inspect}")
  end
end
