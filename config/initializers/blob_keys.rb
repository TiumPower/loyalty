# Khoá blob mang theo đuôi tệp, để CDN chịu cache nó.
#
# Xem lib/blob_key_suffix.rb cho bằng chứng đo được. Chỉ ảnh hưởng blob MỚI —
# blob cũ giữ nguyên khoá và vẫn đọc được bình thường, chỉ là không được CDN
# cache; chúng sẽ được thay dần khi quán tải ảnh mới.
Rails.application.config.to_prepare do
  ActiveStorage::Blob.class_eval do
    def key
      self[:key] ||= begin
        token = self.class.generate_unique_secure_token(
          length: ActiveStorage::Blob::MINIMUM_TOKEN_LENGTH
        )
        "#{token}#{BlobKeySuffix.for(filename: filename, content_type: content_type)}"
      end
    end
  end
end
