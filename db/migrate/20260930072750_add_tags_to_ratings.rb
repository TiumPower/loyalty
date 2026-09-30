class AddTagsToRatings < ActiveRecord::Migration[7.2]
  # What the customer liked, as a short list of keys from Rating::TAGS. The shop
  # page shows the most common ones as "review highlights", which a free-text
  # comment cannot be aggregated into.
  def change
    add_column :ratings, :tags, :jsonb, default: [], null: false
  end
end
