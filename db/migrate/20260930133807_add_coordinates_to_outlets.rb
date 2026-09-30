class AddCoordinatesToOutlets < ActiveRecord::Migration[7.2]
  def change
    # 7 decimal places is ~1cm — far more than a shop front needs, and the
    # precision Nominatim answers with.
    add_column :outlets, :latitude,  :decimal, precision: 10, scale: 7
    add_column :outlets, :longitude, :decimal, precision: 10, scale: 7
    # When the address was last looked up, so a re-save only re-geocodes when
    # the address actually changed.
    add_column :outlets, :geocoded_at, :datetime
    # Set by hand means "leave it alone": an auto lookup must never overwrite a
    # coordinate the merchant corrected.
    add_column :outlets, :geocode_manual, :boolean, default: false, null: false
  end
end
