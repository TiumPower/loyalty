class AddAudienceMemberToBroadcasts < ActiveRecord::Migration[7.2]
  # Gửi thông báo cho ĐÚNG MỘT khách.
  #
  # Nút "Gửi tin nhắn" trong thẻ xem nhanh của một khách vốn mở trình soạn với
  # bộ lọc của cả DANH SÁCH — đứng dưới tên và lịch sử của một người nhưng gửi
  # cho cả nhóm đang lọc. Cùng kiểu cột với audience_outlet_id / audience_tier
  # đã có, để lần gửi theo lịch cũng tìm lại đúng người.
  def change
    add_column :broadcasts, :audience_member_id, :bigint
  end
end
