require "test_helper"

# Mặc định 14 ngày, nhưng người vận hành nâng được cho từng shop: một chuỗi
# nhiều chi nhánh mất hai tuần chỉ để nhập dữ liệu, hai tuần đó trôi qua trước
# khi họ kịp dùng thử thật.
class WorkspaceTrialTest < ActiveSupport::TestCase
  setup { @ws = create(:workspace, status: "trial") }

  test "mặc định là 14 ngày khi chưa đặt riêng" do
    assert_equal Workspace::TRIAL_DAYS, @ws.trial_days
  end

  test "đặt riêng cho từng workspace" do
    @ws.update!(trial_days: 30)
    assert_equal 30, @ws.reload.trial_days
    assert_equal Workspace::TRIAL_DAYS, create(:workspace, subdomain: "other").trial_days
  end

  # Con số mà không dời hạn thì chỉ là trang trí: đồng hồ thật của nhắc hết hạn,
  # xuất hoá đơn và tự ngưng nằm ở paid_until.
  test "đổi số ngày thì dời luôn ngày hết hạn, tính từ lúc bắt đầu" do
    started = 5.days.ago
    @ws.update!(settings: @ws.settings.merge("trial_started_at" => started.iso8601),
                paid_until: started + Workspace::TRIAL_DAYS.days)
    @ws.update!(trial_days: 30)
    assert_in_delta (started + 30.days).to_i, @ws.reload.paid_until.to_i, 5
  end

  # Shop đã trả tiền thì số ngày dùng thử không được đụng vào hạn của họ.
  test "không đụng tới hạn của shop đã kích hoạt" do
    ws = create(:workspace, subdomain: "paid", status: "active", paid_until: 20.days.from_now)
    before = ws.paid_until
    ws.update!(trial_days: 60)
    assert_equal before.to_i, ws.reload.paid_until.to_i
  end

  # Mọi lần lưu khác (bật tự động hoá, đổi branding...) cũng ghi vào settings —
  # nếu bắt theo "settings có đổi" thì mỗi lần như vậy là một lần dời hạn.
  test "sửa thứ khác trong settings không dời hạn" do
    @ws.update!(paid_until: 3.days.from_now)
    before = @ws.paid_until
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    assert_equal before.to_i, @ws.reload.paid_until.to_i
  end

  test "để trống là quay về mặc định" do
    @ws.update!(trial_days: 30)
    @ws.update!(trial_days: "")
    assert_equal Workspace::TRIAL_DAYS, @ws.reload.trial_days
  end

  test "số vô lý bị từ chối" do
    @ws.trial_days = 0
    assert_not @ws.valid?
    @ws.trial_days = 9_999
    assert_not @ws.valid?
  end

  test "start_trial! dùng số ngày của chính workspace" do
    @ws.update!(trial_days: 21)
    @ws.start_trial!
    assert_in_delta 21.days.from_now.to_i, @ws.reload.paid_until.to_i, 5
  end
end
