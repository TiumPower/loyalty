require "test_helper"

# Khoá blob phải mang đuôi tệp, nếu không Cloudflare không cache (nó quyết định
# theo đuôi trong đường dẫn). Đã đo: `…/x.jpg` → MISS rồi HIT, `…/x` → DYNAMIC.
class BlobKeySuffixTest < ActiveSupport::TestCase
  test "lấy đuôi theo content-type" do
    assert_equal ".jpg",  BlobKeySuffix.for(filename: "a.jpeg", content_type: "image/jpeg")
    assert_equal ".png",  BlobKeySuffix.for(filename: "a.png",  content_type: "image/png")
    assert_equal ".webp", BlobKeySuffix.for(filename: "a.png",  content_type: "image/webp")
  end

  # Biến thể do Rails dựng mang tên của ảnh gốc nhưng có thể đã đổi định dạng;
  # tin vào tên tệp sẽ dán ".png" lên một tệp webp.
  test "content-type thắng tên tệp khi hai bên bất đồng" do
    assert_equal ".webp", BlobKeySuffix.for(filename: "anh-goc.png", content_type: "image/webp")
  end

  test "kiểu lạ thì lấy đuôi của tên tệp" do
    assert_equal ".docx", BlobKeySuffix.for(filename: "hop-dong.docx",
                                            content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
  end

  # Không có đuôi nào đáng tin thì thà không gắn gì, còn hơn gắn rác vào khoá.
  test "không đoán bừa" do
    assert_equal "", BlobKeySuffix.for(filename: "khong-duoi", content_type: "application/octet-stream")
    assert_equal "", BlobKeySuffix.for(filename: "", content_type: "")
    assert_equal "", BlobKeySuffix.for(filename: "a.thisisnotanextension", content_type: "application/x-weird")
    assert_equal "", BlobKeySuffix.for(filename: "a./etc/passwd", content_type: "application/x-weird")
  end

  test "blob mới sinh khoá có đuôi" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("square.png").open, filename: "square.png", content_type: "image/png"
    )
    assert blob.key.end_with?(".png"), "khoá là #{blob.key.inspect}"
    assert blob.key.length > ActiveStorage::Blob::MINIMUM_TOKEN_LENGTH
  end

  test "blob đọc lên từ CSDL không bị đổi khoá" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("square.png").open, filename: "square.png", content_type: "image/png"
    )
    key = blob.key
    assert_equal key, ActiveStorage::Blob.find(blob.id).key
  end
end
