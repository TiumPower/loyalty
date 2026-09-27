require "test_helper"

# A merchant can upload their own banner instead of generating one, and every
# banner the campaign has ever shown stays available so an earlier one can be
# put back without uploading it again.
class CampaignBannerLibraryTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "bannerlib", status: "trial")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @campaign = Campaign.create!(workspace: @ws, name: "Khai trương", campaign_type: "promo_voucher",
                                   audience: "all", status: "draft")
    end
    sign_in @user
  end

  test "an uploaded image becomes the banner and is kept in the library" do
    upload_banner("banner-a.png")

    assert_redirected_to merchant_campaign_path(@campaign)
    @campaign.reload
    assert @campaign.banner.attached?
    assert_equal "ready", @campaign.banner_status
    # Nothing composites a QR onto the merchant's own artwork.
    assert_not @campaign.banner_has_qr?
    assert_equal 1, @campaign.banner_library_attachments.count
    assert_equal @campaign.banner.blob.id, @campaign.banner_library_attachments.first.blob_id
  end

  test "a second upload replaces the banner but keeps the first one usable" do
    upload_banner("banner-a.png")
    first_blob_id = @campaign.reload.banner.blob.id

    upload_banner("banner-b.png")
    @campaign.reload

    assert_not_equal first_blob_id, @campaign.banner.blob.id, "the new upload should be on display"
    assert_equal 2, @campaign.banner_library_attachments.count
    assert_includes @campaign.banner_library_attachments.map(&:blob_id), first_blob_id

    # The replaced image must still be downloadable — the point of the library.
    assert ActiveStorage::Blob.service.exist?(ActiveStorage::Blob.find(first_blob_id).key),
           "replacing the banner must not delete the previous file"
  end

  test "an earlier banner can be put back from the library" do
    upload_banner("banner-a.png")
    first_blob_id = @campaign.reload.banner.blob.id
    upload_banner("banner-b.png")

    att = @campaign.reload.banner_library_attachments.find_by(blob_id: first_blob_id)
    patch select_banner_merchant_campaign_path(@campaign, attachment_id: att.id)

    assert_redirected_to merchant_campaign_path(@campaign)
    assert_equal first_blob_id, @campaign.reload.banner.blob.id
    assert_equal 2, @campaign.banner_library_attachments.count, "re-selecting must not duplicate the entry"
  end

  # The public share page adds a standalone QR only when the banner carries
  # none, so that fact has to survive a trip through the library.
  test "re-selecting a generated banner restores its QR flag" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(png_bytes), filename: "ai.png", content_type: "image/png"
    )
    ActsAsTenant.with_tenant(@ws) { @campaign.set_banner!(blob, has_qr: true) }
    assert @campaign.reload.banner_has_qr?

    upload_banner("banner-b.png")
    assert_not @campaign.reload.banner_has_qr?, "an upload carries no composited QR"

    att = @campaign.banner_library_attachments.find_by(blob_id: blob.id)
    patch select_banner_merchant_campaign_path(@campaign, attachment_id: att.id)
    assert @campaign.reload.banner_has_qr?
  end

  test "removing the banner on display leaves the campaign without one" do
    upload_banner("banner-a.png")
    att = @campaign.reload.banner_library_attachments.first

    delete remove_banner_merchant_campaign_path(@campaign, attachment_id: att.id)

    @campaign.reload
    assert_not @campaign.banner.attached?
    assert_nil @campaign.banner_status
    assert_equal 0, @campaign.banner_library_attachments.count
  end

  test "a file that is not an image is refused" do
    patch upload_banner_merchant_campaign_path(@campaign),
          params: { banner: fixture_upload("note.txt", "text/plain") }

    assert_redirected_to merchant_campaign_path(@campaign)
    assert_equal I18n.t("merchant.campaigns.banner_upload_bad_type"), flash[:alert]
    assert_not @campaign.reload.banner.attached?
  end

  test "the library is capped so banners cannot pile up forever" do
    limit = Campaign::BANNER_LIBRARY_LIMIT
    ActsAsTenant.with_tenant(@ws) do
      (limit + 2).times do |i|
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(png_bytes), filename: "b#{i}.png", content_type: "image/png"
        )
        @campaign.set_banner!(blob, has_qr: false)
      end
    end
    perform_enqueued_jobs

    assert_equal limit, @campaign.reload.banner_library_attachments.count
    assert @campaign.banner.attached?, "the banner on display must survive the pruning"
  end

  test "a campaign created with an uploaded banner shows it straight away" do
    assert_difference -> { ActsAsTenant.with_tenant(@ws) { Campaign.count } }, 1 do
      post merchant_campaigns_path, params: {
        campaign: { name: "Có ảnh sẵn", campaign_type: "event", audience: "all", status: "draft" },
        banner: fixture_upload("banner-a.png", "image/png")
      }
    end
    campaign = ActsAsTenant.with_tenant(@ws) { Campaign.order(:created_at).last }
    assert campaign.banner.attached?
    assert_equal 1, campaign.banner_library_attachments.count
  end

  private

  def upload_banner(name)
    patch upload_banner_merchant_campaign_path(@campaign),
          params: { banner: fixture_upload(name, "image/png") }
  end

  # Built on the fly so the repo does not carry binary fixtures for this.
  def fixture_upload(name, content_type)
    body = content_type.start_with?("image/") ? png_bytes : "khong phai anh"
    file = Tempfile.new([File.basename(name, ".*"), File.extname(name)])
    file.binmode
    file.write(body)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, original_filename: name)
  end

  # Smallest valid PNG: 1×1 transparent pixel.
  def png_bytes
    Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )
  end
end
