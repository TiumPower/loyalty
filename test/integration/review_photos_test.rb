require "test_helper"

# "Add visit photos" from the design. The photos land on the public shop page,
# so the cap and the accepted types are enforced server-side, not just in the
# picker.
class ReviewPhotosTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "shots")
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @ws.update!(settings: @ws.settings.merge("feedback_public" => true))
    end
    sign_in_member("shot@example.com")
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member(email)
    post "#{base}/login", params: { email: email }
    code = ActsAsTenant.with_tenant(@ws) { OtpChallenge.order(:created_at).last.code }
    post "#{base}/verify", params: { code: code }
  end

  def jpeg(name = "shot.jpg")
    Rack::Test::UploadedFile.new(
      Rails.root.join("db/seed_images/reward_coffee.jpg"), "image/jpeg", false, original_filename: name
    )
  end

  test "a review can carry photos" do
    post "#{base}/review", params: { stars: 5, comment: "Ngon", photos: [jpeg, jpeg("two.jpg")] }
    rating = ActsAsTenant.with_tenant(@ws) { Rating.order(:id).last }
    assert_equal 2, rating.photos.attachments.size
  end

  # The picker caps at four, but the form posts whatever is in the DOM.
  test "more photos than the cap are trimmed, not rejected" do
    files = Array.new(Rating::MAX_PHOTOS + 2) { |i| jpeg("s#{i}.jpg") }
    post "#{base}/review", params: { stars: 4, comment: "Ổn", photos: files }
    rating = ActsAsTenant.with_tenant(@ws) { Rating.order(:id).last }
    assert_not_nil rating, "the review itself must still be saved"
    assert_equal Rating::MAX_PHOTOS, rating.photos.attachments.size
    assert_equal "Ổn", rating.comment
  end

  test "a review with no photos still works" do
    assert_difference -> { ActsAsTenant.with_tenant(@ws) { Rating.count } }, 1 do
      post "#{base}/review", params: { stars: 3, comment: "Bình thường" }
    end
  end
end
