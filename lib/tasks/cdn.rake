# Gắn Cache-Control cho những tệp đã nằm sẵn trên R2.
#
# Mọi upload MỚI đã mang header (xem `upload:` trong config/storage.yml),
# nhưng tệp cũ thì không — và thiếu nó Cloudflare trả `cf-cache-status: DYNAMIC`
# rồi đi hỏi R2 lại mỗi lượt, tức là có CDN mà không được cache.
#
# Copy đè lên chính nó với `metadata_directive: REPLACE`: S3/R2 làm việc này ở
# phía máy chủ, không tệp nào phải tải về rồi đẩy lên lại.
#
#   cap production deploy:cdn_headers      (hoặc)
#   RAILS_ENV=production bin/rails loyalty:cdn_headers
namespace :loyalty do
  desc "Gắn Cache-Control cho tệp R2 đã upload trước đây"
  task cdn_headers: :environment do
    service = CdnRoutes.storage_behind(ActiveStorage::Blob.service)
    unless service.respond_to?(:public_host)
      abort "Kho hiện tại không phải R2 có tiền tố (#{service.class}) — không có gì để vá."
    end

    cache = "public, max-age=31536000, immutable"
    bucket = service.bucket
    done = skipped = failed = 0

    ActiveStorage::Blob.find_each do |blob|
      key = service.prefixed(blob.key)
      object = bucket.object(key)
      unless object.exists?
        skipped += 1
        next
      end
      if object.cache_control == cache
        skipped += 1
        next
      end
      # copy_from lên chính nó: R2 ghi lại metadata mà không chuyển byte.
      object.copy_from(object, cache_control: cache, content_type: blob.content_type,
                               metadata_directive: "REPLACE")
      done += 1
    rescue StandardError => e
      failed += 1
      warn "  #{key}: #{e.class} #{e.message}"
    end

    puts "Cache-Control: #{done} tệp đã vá, #{skipped} bỏ qua (đã có hoặc không tồn tại), #{failed} lỗi."
  end
end
