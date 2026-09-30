class AddPillColoursToTiers < ActiveRecord::Migration[7.2]
  def change
    # The tier badge in the design is a soft tinted pill with coloured
    # lettering, which is a different palette from the saturated gradient the
    # hexagon crest uses — and not derivable from it (gold's pill is yellow with
    # terracotta text; diamond's is pink with black). So the pill carries its
    # own two colours, and falls back to the gradient when they are blank.
    add_column :tiers, :pill_bg,     :string
    add_column :tiers, :pill_fg,     :string
    # Only the gold pill is ringed in the design — its pale yellow sits too
    # close to the page. Optional, so the others simply have none.
    add_column :tiers, :pill_border, :string
  end
end
