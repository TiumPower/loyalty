class AddPushCountToBroadcasts < ActiveRecord::Migration[7.2]
  # Bao nhiêu khách thật sự nhận được thông báo ĐẨY, ghi lại lúc gửi.
  #
  # Trước đây danh sách chỉ hiện `sent_count` kèm chữ "10 khách", mà con số đó
  # là số thư vào hộp thư trong ứng dụng. Chủ quán đọc ra "10 người đã nhận
  # thông báo" rồi không hiểu vì sao điện thoại không reo — trong khi không ai
  # trong nhóm đó cài app.
  #
  # Để nullable: các bản gửi CŨ không có số này, và 0 là một lời nói dối khác
  # ("đẩy tới 0 người") so với "không biết".
  def change
    add_column :broadcasts, :push_count, :integer
  end
end
