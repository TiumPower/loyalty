module Merchant
  # Bulk-edit membership tiers (name, threshold, points multiplier, colors).
  class TiersController < BaseController
    before_action :require_manager!

    # Every row used to be written with its return value dropped, so a refused
    # save still redirected with "Đã lưu cấu hình" — and an out-of-range number
    # got past validation entirely and came back as a 500 from Postgres. Now the
    # whole grid is applied in one transaction and rolled back as a unit, so the
    # merchant never ends up with half their tiers changed.
    def update
      rows   = params.fetch(:tiers, {})
      tiers  = current_workspace.tiers.ordered.to_a
      errors = []

      Tier.transaction do
        tiers.each do |tier|
          attrs = rows[tier.id.to_s]
          next if attrs.blank?
          tier.assign_attributes(
            name:             attrs[:name].presence || tier.name,
            threshold_points: attrs[:threshold_points],
            multiplier:       attrs[:multiplier],
            benefits:         parse_benefits(attrs[:benefits]),
            gradient_from:    attrs[:gradient_from].presence || tier.gradient_from,
            gradient_to:      attrs[:gradient_to].presence   || tier.gradient_to
          )
          errors.concat(tier.errors.full_messages.map { |m| "#{tier.name}: #{m}" }) unless tier.save
        end
        errors.concat(threshold_order_errors(tiers))
        raise ActiveRecord::Rollback if errors.any?
      end

      return redirect_to merchant_loyalty_program_path, notice: t("merchant.tiers.saved") if errors.empty?
      redirect_to merchant_loyalty_program_path, alert: errors.first(3).join(" · ")
    end

    private

    def nav_key = :program

    # One perk per line (newline-separated).
    def parse_benefits(raw) = raw.to_s.split(/[\r\n]+/).map(&:strip).reject(&:blank?)

    # Thresholds have to climb with position or the rungs stop making sense:
    # next_tier walks the ladder in order, so a gold rung set below silver told
    # a bronze customer the wrong target and drew the wrong progress bar.
    def threshold_order_errors(tiers)
      tiers.sort_by(&:position).each_cons(2).filter_map do |lower, higher|
        next if higher.threshold_points > lower.threshold_points
        t("merchant.tiers.threshold_order", higher: higher.name, lower: lower.name)
      end
    end
  end
end
