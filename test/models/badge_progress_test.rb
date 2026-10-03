require "test_helper"

# `progress_for` hỏi cơ sở dữ liệu một lần cho MỖI huy hiệu. Dải huy hiệu nằm
# trên màn hình chính — trang khách mở nhiều nhất — nên nếu để nguyên cách đó
# thì mỗi huy hiệu quán tạo thêm là một câu truy vấn nữa, mỗi lần mở app.
class BadgeProgressTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "bprog")
    ActsAsTenant.with_tenant(@ws) do
      @member = create(:member, workspace: @ws, email: "bp@example.com")
      @member.update!(lifetime_points: 300)
    end
  end

  def badges(type, count, threshold)
    ActsAsTenant.with_tenant(@ws) do
      Array.new(count) do |i|
        Badge.create!(workspace: @ws, key: "#{type}#{i}", name: "HH#{i}",
                      criteria_type: type, threshold: threshold, position: i)
      end
    end
  end

  def count_queries
    n = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      n += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end
    yield
    n
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  test "mười huy hiệu không tốn mười câu truy vấn" do
    list = badges("purchases_count", 10, 5)
    queries = ActsAsTenant.with_tenant(@ws) { count_queries { Badge.progress_map(list, @member) } }
    assert_operator queries, :<=, 2, "đếm một lần rồi suy ra, không hỏi lại cho từng huy hiệu"
  end

  # Kết quả phải trùng từng con số với đường cũ, nếu không đây là tối ưu đổi
  # lấy sai số.
  test "cho ra đúng cùng kết quả với progress_for" do
    list = ActsAsTenant.with_tenant(@ws) do
      badges("points_total", 2, 100) + badges("purchases_count", 2, 3) +
        badges("night_owl", 1, 2) + badges("first_purchase", 1, 1)
    end
    ActsAsTenant.with_tenant(@ws) do
      map = Badge.progress_map(list, @member)
      list.each { |b| assert_equal b.progress_for(@member), map[b], b.criteria_type }
    end
  end

  # Mốc 0 thì chia cho 0 — thứ tự "gần đạt nhất" trên màn hình chính dựa vào
  # tỉ lệ này.
  test "mốc bằng 0 không làm nổ phép chia" do
    list = badges("purchases_count", 1, 0)
    ActsAsTenant.with_tenant(@ws) do
      assert_equal [0, 0], Badge.progress_map(list, @member)[list.first]
    end
  end
end
