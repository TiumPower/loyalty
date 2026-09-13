class Outlet < ApplicationRecord
  acts_as_tenant(:workspace)

  belongs_to :workspace
  has_many :memberships, dependent: :nullify

  # Purchases, point transactions, ratings and vouchers all reference an outlet
  # with a foreign key, so deleting a branch that has traded raises
  # InvalidForeignKey — the database protects the history, but the app used to
  # turn that into a 500. A branch that has history is deactivated, not deleted.
  def history_count
    @history_count ||= Purchase.unscoped.where(outlet_id: id).count +
                       PointTransaction.unscoped.where(outlet_id: id).count +
                       Rating.unscoped.where(outlet_id: id).count +
                       Voucher.unscoped.where(used_outlet_id: id).count
  end

  def destroyable? = history_count.zero?

  validates :name, presence: true

  scope :active, -> { where(active: true) }
end
