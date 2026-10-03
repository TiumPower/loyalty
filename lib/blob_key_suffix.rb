# Đuôi tệp để gắn vào khoá của một blob.
#
# Active Storage sinh khoá là 28 ký tự ngẫu nhiên, không đuôi. Cloudflare
# quyết định cache theo ĐUÔI TỆP trong đường dẫn, nên mọi ảnh đều rơi vào
# `cf-cache-status: DYNAMIC` — có CDN mà không bao giờ được cache. Đã kiểm
# chứng: cùng bucket, cùng host, cùng header, cùng lúc, `…/cdn-probe.jpg` trả
# MISS rồi HIT còn `…/cdn-probe-noext` trả DYNAMIC cả hai lần.
#
# Lấy đuôi từ CONTENT-TYPE trước, tên tệp sau: biến thể do Rails dựng mang tên
# của ảnh gốc nhưng có thể đã đổi định dạng, nên tin vào tên tệp sẽ đặt `.png`
# lên một tệp webp.
module BlobKeySuffix
  # Đủ dài để nhận ra, đủ ngắn để không ai nhét đường dẫn vào đây.
  SAFE = /\A\.[a-z0-9]{1,5}\z/

  FROM_TYPE = {
    "image/jpeg"      => ".jpg",
    "image/png"       => ".png",
    "image/webp"      => ".webp",
    "image/gif"       => ".gif",
    "image/avif"      => ".avif",
    "image/svg+xml"   => ".svg",
    "image/heic"      => ".heic",
    "application/pdf" => ".pdf",
  }.freeze

  def self.for(filename:, content_type:)
    known = FROM_TYPE[content_type.to_s.split(";").first.to_s.strip.downcase]
    return known if known

    ext = File.extname(filename.to_s).downcase
    ext.match?(SAFE) ? ext : ""
  end
end
