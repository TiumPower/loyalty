require "test_helper"

# Mũi tên back trong PWA từng là link cứng về một trang định sẵn: vào trang cá
# nhân, vào thông báo, bấm back thì ra thẳng màn hình chính — khách mất chỗ
# mình đang đứng. href trên nút chỉ nói màn đó THƯỜNG đến từ đâu, không nói
# khách vừa rời đi từ đâu.
#
# Sửa xong một lượt thì màn mới thêm sau vẫn sẽ chép lại cái cũ, nên chốt bằng
# cách quét thẳng file view: nút back nào cũng phải gắn controller `goback`.
class CustomerBackLinksTest < ActiveSupport::TestCase
  # Màn cảm ơn sau khi gửi đánh giá: lùi theo lịch sử là quay về chính biểu mẫu
  # vừa gửi xong, nên nó cố ý đi tới trang giới thiệu quán.
  EXEMPT = %w[app/views/customer/reviews/thanks.html.erb].freeze

  test "mọi nút back trong PWA đều lùi theo lịch sử" do
    offenders = Dir["app/views/customer/**/*.html.erb"].sort.reject { |f| EXEMPT.include?(f) }.flat_map do |file|
      lines = File.readlines(file, encoding: "UTF-8")
      lines.each_with_index.filter_map do |line, i|
        next unless line.include?("l-iconbtn") && line.include?("link_to")
        # Nút back là nút có mũi tên trái bên trong — các l-iconbtn khác (chia
        # sẻ, đóng, tải lại) không liên quan.
        # Khai báo link có thể trải vài dòng, nên đọc cả cụm chứ không chỉ dòng đầu.
        decl = lines[i, 4].join
        next unless decl.include?("arrow_left")
        "#{file}:#{i + 1}" unless decl.include?("goback")
      end
    end

    assert_empty offenders, <<~MSG
      Những nút back này vẫn là link cứng, bấm vào sẽ nhảy về một trang định sẵn
      thay vì quay lại trang trước:
      #{offenders.join("\n")}
      Thêm: data: { controller: "goback", action: "goback#back" }
    MSG
  end

  # Giữ href lại làm đường lui: tab mở thẳng vào màn này (quét QR, bấm link
  # trong Zalo) thì không có gì để lùi.
  test "nút back vẫn giữ href làm đường lui" do
    src = File.read("app/views/customer/notifications/index.html.erb", encoding: "UTF-8")
    assert_match(/link_to member_root_path.*goback/m, src.lines[3])
  end
end
