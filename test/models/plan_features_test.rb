require "test_helper"

# Trang Doanh thu của merchant liệt kê "Gói ... đang mở những gì". Danh sách đó
# từng được dựng bằng cách dò mọi cột `allow_*` của bảng plans, nên nó quảng cáo
# cả "Thử nghiệm A/B" — cột thì có, còn tính năng thì chưa ai viết một dòng.
# Trên một trang bán gói, hứa một thứ không tồn tại là chuyện khác hẳn một ô
# thừa.
class PlanFeaturesTest < ActiveSupport::TestCase
  test "mọi tính năng được quảng cáo đều có cột tương ứng trên gói" do
    Workspace::PLAN_FEATURES.each do |f|
      assert Plan.new.respond_to?("allow_#{f}"), "gói không có cột allow_#{f}"
    end
  end

  # Cái bẫy ban đầu: một cột mới thêm vào bảng plans tự động biến thành một dòng
  # quảng cáo. Danh sách phải do người viết chọn, không do schema quyết.
  test "cột allow_ mới không tự biến thành lời quảng cáo" do
    columns = Plan.column_names.grep(/\Aallow_/).map { |c| c.delete_prefix("allow_").to_sym }
    extra = columns - Workspace::PLAN_FEATURES
    assert_includes extra, :ab_testing,
                    "test này giả định cột allow_ab_testing vẫn còn mà không được quảng cáo"
  end

  # Tính năng chưa tồn tại thì không được chặn theo gói: nếu không, một chỗ nào
  # đó gọi plan_allows?(:ab_testing) sẽ khoá người dùng khỏi hư không.
  test "tính năng ngoài danh sách thì không chặn ai" do
    ws = create(:workspace, plan: "starter")
    assert ws.plan_allows?(:ab_testing)
    assert ws.plan_allows?(:chuyen_khong_co_that)
  end
end
