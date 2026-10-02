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
    # `public_host` là domain tuỳ chỉnh gắn trước bucket công khai (ví dụ
    # https://img.tiumpower.com). Có nó thì service trở thành "công khai": URL
    # phát ra là đường dẫn CDN vĩnh viễn, không ký tên, không hạn dùng.
    attr_reader :public_host

    def initialize(prefix:, public_host: nil, **options)
      @prefix = prefix.to_s.delete_prefix("/").chomp("/")
      @public_host = public_host.presence&.chomp("/")
      super(**options)
      return if @public_host.nil?

      @public = true
      # S3Service gắn ACL "public-read" cho service công khai. R2 KHÔNG có ACL
      # trên object — gửi lên là mọi upload chết. Quyền công khai ở R2 là thuộc
      # tính của bucket, bật trong bảng điều khiển Cloudflare.
      @upload_options.delete(:acl)
    end

    # URL công khai qua domain tuỳ chỉnh. Mặc định của S3Service là
    # `object.public_url`, trỏ vào endpoint S3 của R2 — nơi KHÔNG phục vụ công
    # khai kể cả khi bucket đã mở; đường công khai duy nhất là r2.dev hoặc
    # domain tuỳ chỉnh.
    def public_url(key, **)
      "#{@public_host}/#{prefixed(key)}"
    end

    def delete_prefixed(prefix)
      super(prefixed(prefix))
    end

    def prefixed(key)
      return key if @prefix.empty?
      key.to_s.start_with?("#{@prefix}/") ? key : "#{@prefix}/#{key}"
    end

    private

    def object_for(key)
      super(prefixed(key))
    end

    def upload_stream(key:, **options, &block)
      super(key: prefixed(key), **options, &block)
    end
  end
end
