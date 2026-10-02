# Phát thẳng URL CDN cho ảnh, thay vì cho trình duyệt đi vòng qua Rails.
#
# Active Storage chỉ cho chọn giữa hai lối: `rails_storage_proxy` (Rails tải
# tệp về rồi phát lại — mỗi ảnh giữ một thread Puma) và `rails_storage_redirect`
# (Rails trả 302 — nhẹ hơn, nhưng vẫn một lượt đi tới Rails cho mỗi ảnh, và
# `src` trong HTML vẫn là đường dẫn Rails). Bucket R2 giờ đã công khai sau
# `img.tiumpower.com`, nên không cần lượt nào cả.
#
# Cắm vào bằng một route `direct` nên KHÔNG phải sửa chỗ nào đang gọi
# `image_tag`/`url_for` — Rails hỏi resolver này cho mọi blob và mọi biến thể.
#
# Quan trọng: một biến thể CHƯA được tạo thì chưa có tệp trên R2, và URL CDN
# của nó sẽ 404. Những trường hợp đó rơi về đường redirect của Rails — lượt
# truy cập đầu tạo biến thể rồi lưu lại, lần sau đã có bản ghi nên đi thẳng
# CDN. Tự lành, không ai phải chạy lệnh dựng lại gì.
module CdnRoutes
  module_function

  # → URL CDN, hoặc nil nếu chưa phục vụ thẳng được (service riêng tư, biến
  # thể chưa tạo, hoặc một loại model không nhận ra).
  def url_for(model)
    case model
    when ActiveStorage::Blob
      cdn_url(model)
    when ActiveStorage::VariantWithRecord
      processed?(model) ? cdn_url(model.image&.blob) : nil
    end
  rescue StandardError => e
    # URL ảnh không bao giờ được làm chết cả trang. Trả nil là Rails dùng
    # đường cũ.
    Rails.logger.warn("[CdnRoutes] #{e.class}: #{e.message}")
    nil
  end

  # Biến thể đã dựng chưa? Hỏi thẳng bảng variant_records thay vì gọi
  # `processed?` (Rails để private) hay `processed` (sẽ DỰNG biến thể ngay
  # trong lúc render HTML — đúng thứ cần tránh).
  def processed?(variant)
    variant.blob.variant_records.exists?(variation_digest: variant.variation.digest)
  end

  def cdn_url(blob)
    return nil if blob.nil?
    service = storage_behind(blob.service)
    return nil unless service.respond_to?(:public_host) && service.public_host.present?
    blob.url
  end

  # Kho thật nằm sau lớp nào.
  #
  # Service của blob ở đây là Mirror (R2 là chính, đĩa máy chủ là bản sao cho
  # bản sao lưu đêm). Mirror không có `public_host` — nó uỷ quyền `url` xuống
  # primary — nên hỏi thẳng Mirror thì lúc nào cũng ra "không công khai", và
  # mọi ảnh lặng lẽ quay về đường cũ.
  MAX_DEPTH = 4
  def storage_behind(service)
    MAX_DEPTH.times do
      break unless service.respond_to?(:primary)
      service = service.primary
    end
    service
  end
end
