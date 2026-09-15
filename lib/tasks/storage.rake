# Chuyển tệp Active Storage từ đĩa máy chủ sang DigitalOcean Spaces.
#
# Chạy được nhiều lần: tệp nào đã có trên Spaces thì bỏ qua. Mỗi blob sau khi
# chép xong mới đổi `service_name` — nên nếu task dừng giữa chừng, các tệp chưa
# chép vẫn đọc từ đĩa như cũ, app không hỏng.
#
#   bin/rails storage:check                 # thử kết nối Spaces
#   DRY=1 bin/rails storage:to_spaces       # xem sẽ chép bao nhiêu, không ghi
#   bin/rails storage:to_spaces             # chép thật
namespace :storage do
  desc "Kiểm tra kết nối tới DigitalOcean Spaces"
  task check: :environment do
    service = spaces_service
    key = "connection-check/#{SecureRandom.hex(8)}"
    service.upload(key, StringIO.new("ok"), content_type: "text/plain")
    ok = service.download(key) == "ok"
    service.delete(key)
    puts ok ? "✓ Spaces OK — bucket #{ENV['SPACES_BUCKET']} (#{ENV.fetch('SPACES_REGION', 'sgp1')})" : "✗ Ghi được nhưng đọc lại sai."
  end

  desc "Chép mọi tệp đang nằm trên đĩa lên Spaces (DRY=1 để chạy thử)"
  task to_spaces: :environment do
    dry    = ENV["DRY"].present?
    # Ghi thẳng lên Spaces (kho chính) — tệp vốn đã nằm trên đĩa, cho đi qua
    # Mirror nữa chỉ tổ chép lại đúng những byte đó xuống chính chỗ cũ.
    target = spaces_service
    # …nhưng blob phải trỏ về kho MẶC ĐỊNH của app (production: spaces_mirrored),
    # để mọi thao tác sau này (ghi đè, xoá) còn đi qua mirror như tệp mới.
    target_name = Rails.configuration.active_storage.service.to_s
    disk   = ActiveStorage::Blob.services.fetch(:local)

    pending = ActiveStorage::Blob.where.not(service_name: target_name)
    total   = pending.count
    puts "#{total} tệp chưa nằm trên Spaces.#{' (chạy thử — không ghi gì)' if dry}"

    copied = skipped = missing = failed = 0
    pending.find_each.with_index(1) do |blob, i|
      if target.exist?(blob.key)
        # Đã có sẵn trên Spaces (lần chạy trước dừng giữa chừng) — chỉ cần
        # trỏ blob sang đúng service.
        blob.update_columns(service_name: target_name) unless dry
        skipped += 1
      elsif !disk.exist?(blob.key)
        # Bản ghi còn nhưng tệp đã mất trên đĩa — báo để xoá dọn riêng.
        missing += 1
        warn "  ? thiếu tệp trên đĩa: #{blob.key} (#{blob.filename})"
      elsif dry
        copied += 1
      else
        disk.open(blob.key, checksum: blob.checksum) do |file|
          target.upload(blob.key, file, checksum: blob.checksum,
                        content_type: blob.content_type, filename: blob.filename)
        end
        blob.update_columns(service_name: target_name)
        copied += 1
      end
      print "\r  #{i}/#{total}…" if (i % 20).zero?
    rescue StandardError => e
      failed += 1
      warn "\n  ✗ #{blob.key} (#{blob.filename}): #{e.class} #{e.message}"
    end

    puts "\nXong: #{copied} chép, #{skipped} đã có sẵn, #{missing} thiếu tệp gốc, #{failed} lỗi."
    puts "Còn #{ActiveStorage::Blob.where.not(service_name: target_name).count} blob chưa ở trên Spaces."
  end

  desc "Kiểm tra mọi tệp Active Storage đều đọc được từ kho đang dùng"
  task verify: :environment do
    ok = 0
    broken = []
    ActiveStorage::Blob.find_each do |blob|
      blob.service.download(blob.key).bytesize
      ok += 1
    rescue StandardError => e
      broken << [blob.key, blob.service_name, blob.filename.to_s, "#{e.class}"]
    end
    puts "Đọc được #{ok} tệp, hỏng #{broken.size}."
    broken.first(20).each { |key, svc, name, err| puts "  ✗ #{key} [#{svc}] #{name} — #{err}" }
    abort "Có tệp không đọc được." if broken.any?
  end

  def spaces_service
    unless ENV["SPACES_KEY"].present? && ENV["SPACES_BUCKET"].present?
      abort "Thiếu SPACES_KEY / SPACES_BUCKET trong .env — xem config/storage.yml."
    end
    ActiveStorage::Blob.services.fetch(:spaces)
  end
end
