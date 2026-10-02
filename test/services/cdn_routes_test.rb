require "test_helper"

# Ảnh phát thẳng từ CDN thay vì đi vòng qua Rails — nhưng chỉ khi thật sự phát
# được, vì một URL CDN trỏ vào tệp chưa tồn tại là một ảnh vỡ.
class CdnRoutesTest < ActiveSupport::TestCase
  def public_service(host: "https://img.tiumpower.com")
    ActiveStorage::Service::PrefixedS3Service.new(
      prefix: "loyalty", public_host: host, bucket: "tiumpower",
      access_key_id: "k", secret_access_key: "s", region: "auto",
      endpoint: "https://example.r2.cloudflarestorage.com", force_path_style: true
    )
  end

  test "không có domain công khai thì service vẫn riêng tư như cũ" do
    svc = public_service(host: nil)
    assert_not svc.public?
    assert_nil svc.public_host
  end

  test "có domain công khai thì URL là đường CDN, kèm tiền tố của app" do
    svc = public_service
    assert svc.public?
    assert_equal "https://img.tiumpower.com/loyalty/abc123", svc.url("abc123")
  end

  # R2 không có ACL trên object. S3Service gắn "public-read" cho mọi service
  # công khai, và R2 từ chối — mọi upload sẽ chết chứ không chỉ mất quyền.
  test "không gửi ACL lên R2" do
    assert_not public_service.instance_variable_get(:@upload_options).key?(:acl)
  end

  # Thiếu header này thì Cloudflare trả `cf-cache-status: DYNAMIC` và đi hỏi R2
  # lại mỗi lượt — tức là có CDN mà không được cache.
  test "cấu hình thật có dặn CDN cache vĩnh viễn" do
    opts = ActiveStorage::Blob.services.fetch(:spaces)
                              .instance_variable_get(:@upload_options)
    assert_equal "public, max-age=31536000, immutable", opts[:cache_control]
  end

  test "dấu / thừa ở cuối domain không tạo ra // trong URL" do
    svc = public_service(host: "https://img.tiumpower.com/")
    assert_equal "https://img.tiumpower.com/loyalty/abc123", svc.url("abc123")
  end

  # Ở môi trường test service là Disk, nên resolver phải nhường đường cho Rails.
  test "service không công khai thì nhường lại cho Rails" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x"), filename: "a.txt", content_type: "text/plain"
    )
    assert_nil CdnRoutes.url_for(blob)
  end

  # Biến thể chưa dựng thì chưa có tệp trên R2; phát URL CDN lúc này là ảnh vỡ.
  test "biến thể chưa dựng thì không phát URL CDN" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("square.png").open, filename: "square.png", content_type: "image/png"
    )
    variant = blob.variant(resize_to_limit: [10, 10])
    assert_not CdnRoutes.processed?(variant), "chưa dựng"
    assert_nil CdnRoutes.url_for(variant)

    variant.processed
    assert CdnRoutes.processed?(variant), "dựng xong thì có bản ghi"
  end

  # Kiểm tra `processed?` không được VÔ TÌNH dựng biến thể: làm vậy là chuyển
  # việc nén ảnh vào giữa lúc render HTML.
  test "hỏi biến thể đã dựng chưa thì không dựng nó" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("square.png").open, filename: "square.png", content_type: "image/png"
    )
    variant = blob.variant(resize_to_limit: [11, 11])
    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      CdnRoutes.processed?(variant)
      CdnRoutes.url_for(variant)
    end
  end

  test "lỗi bất ngờ không làm chết trang, chỉ mất đường tắt" do
    broken = Object.new
    def broken.is_a?(k) = k == ActiveStorage::Blob
    assert_nil CdnRoutes.url_for(broken)
  end
end
