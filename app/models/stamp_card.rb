class StampCard < ApplicationRecord
  acts_as_tenant(:workspace)
  # Refuses a reward that is off / sold out / ended (see the concern).
  include AssignableReward

  belongs_to :workspace
  belongs_to :reward, optional: true
  has_many :stamp_card_memberships, dependent: :destroy

  validates :title, presence: true
  validates :target_count, numericality: { greater_than: 1 }

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def running?
    now = Time.current
    active? && (starts_at.nil? || starts_at <= now) && (ends_at.nil? || ends_at >= now)
  end

  def display_icon = icon.presence || "🎟️"

  def membership_for(member)
    stamp_card_memberships.find_or_create_by!(member: member) { |m| m.workspace = workspace }
  end
end
