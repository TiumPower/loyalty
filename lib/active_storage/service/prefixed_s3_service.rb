require "active_storage/service/s3_service"

module ActiveStorage
  # S3Service có thêm tiền tố thư mục.
  #
  # Bucket `czin` dùng chung cho nhiều app (boidat, xstudio, estate, loyalty…),
  # mà ActiveStorage::Service::S3Service không có tuỳ chọn prefix: mọi app đổ
  # khoá ngẫu nhiên 28 ký tự thẳng vào gốc bucket. Không đụng nhau — khoá là
  # ngẫu nhiên — nhưng nhìn vào bucket thì không biết tệp nào của app nào, và
  # không đặt được lifecycle hay xoá gọn dữ liệu của riêng một app.
  #
  # Tiền tố nằm ở tầng service chứ không ghi vào cột `key`, nên dữ liệu trong
  # CSDL không đổi và bỏ tiền tố sau này chỉ là đổi cấu hình.
  #
  # Ba đường phải chặn, không chỉ một: hầu hết thao tác đi qua `object_for`,
  # nhưng `delete_prefixed` gọi thẳng `bucket.objects(prefix:)`, còn
  # `upload_stream` đi vòng qua TransferManager khi aws-sdk đủ mới. Bỏ sót một
  # trong ba là tệp rơi ra ngoài tiền tố mà không báo lỗi gì.
  class Service::PrefixedS3Service < Service::S3Service
    def initialize(prefix:, **options)
      @prefix = prefix.to_s.delete_prefix("/").chomp("/")
      super(**options)
    end

    def delete_prefixed(prefix)
      super(prefixed(prefix))
    end

    private

    def object_for(key)
      super(prefixed(key))
    end

    def upload_stream(key:, **options, &block)
      super(key: prefixed(key), **options, &block)
    end

    def prefixed(key)
      return key if @prefix.empty?
      key.to_s.start_with?("#{@prefix}/") ? key : "#{@prefix}/#{key}"
    end
  end
end
