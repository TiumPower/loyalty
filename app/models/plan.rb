class Plan < ApplicationRecord
  validates :key, :name, presence: true
  validates :key, uniqueness: true

  scope :ordered, -> { order(:position, :price) }

  DEFAULTS = [
    { key: "starter", name: "Starter", price: 199_000, position: 0,
      max_outlets: 1, max_members: 500,
      allow_stamps: true, allow_gamification: false, allow_campaigns: false,
      allow_custom_domain: false, allow_ab_testing: false,
      features: [ "1 chi nhánh", "Points + Tiers + Stamp", "Tối đa 500 khách", "Máy quét tại quầy" ] },
    { key: "growth", name: "Growth", price: 499_000, position: 1,
      max_outlets: 5, max_members: nil,
      allow_stamps: true, allow_gamification: true, allow_campaigns: true,
      allow_custom_domain: false, allow_ab_testing: false,
      features: [ "5 chi nhánh", "Đủ 4 cơ chế loyalty", "Không giới hạn khách", "Campaign + mã QR phát hành", "CRM & thông báo" ] },
    { key: "scale", name: "Scale", price: 1_290_000, position: 2,
      max_outlets: nil, max_members: nil,
      allow_stamps: true, allow_gamification: true, allow_campaigns: true,
      allow_custom_domain: true, allow_ab_testing: true,
      features: [ "Không giới hạn chi nhánh", "Tên miền riêng", "Ưu tiên hỗ trợ" ] }
  ].freeze

  # The cheapest plan whose allow_<feature> flag is on (reads real plan data,
  # so the "upgrade" message always names the correct plan). nil if none.
  def self.lowest_allowing(feature)
    col = "allow_#{feature}"
    return nil unless column_names.include?(col)
    ordered.detect { |p| p.public_send(col) }
  end

  def self.for(key)
    find_by(key: key) || new(DEFAULTS.find { |d| d[:key] == key } || DEFAULTS.first)
  end

  def self.seed_defaults!
    DEFAULTS.each do |attrs|
      plan = find_or_initialize_by(key: attrs[:key])
      plan.assign_attributes(attrs) if plan.new_record?
      plan.save!
    end
  end

  def unlimited_outlets? = max_outlets.nil?
  def unlimited_members? = max_members.nil?
  def price_label = "#{ActiveSupport::NumberHelper.number_to_delimited(price)}đ"

  # Localized feature list (falls back to the stored VN features).
  def localized_features
    vals = I18n.t("merchant.plans.#{key}.features", default: nil)
    vals.is_a?(Array) ? vals : features
  end
end
