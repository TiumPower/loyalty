require "test_helper"

# Thanh menu merchant: chín mục, mỗi màn hình nằm trong đúng một mục.
# Một màn không thuộc mục nào là một màn không ai tới được.
class MerchantNavTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace, subdomain: "nav")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: @user, workspace: @ws, role: "owner") }
    sign_in @user
  end

  def sections
    get merchant_root_path
    ActsAsTenant.with_tenant(@ws) { @controller.view_context.merchant_sections }
  end

  test "đúng chín mục, theo đúng thứ tự đã chốt" do
    assert_equal %i[overview customers loyalty marketing vouchers operations admin settings],
                 sections.map { |s| s[:key] }
  end

  # Cái dễ hỏng nhất khi sắp xếp lại menu: một màn bị rơi ra ngoài mọi mục.
  test "mọi màn hình trong menu đều mở được" do
    missing = []
    sections.each do |sec|
      sec[:items].each do |key, label, path, _|
        get path
        missing << "#{sec[:key]}/#{key} → #{path} (#{response.status})" unless response.successful? || response.redirect?
      end
    end
    assert_empty missing, "những màn này không mở được:\n#{missing.join("\n")}"
  end

  # Mỗi màn tự khai nav_key; nếu nav_key đó không nằm trong mục nào thì trang
  # mở ra mà menu không sáng chỗ nào, và dải tab phía trên biến mất.
  test "mọi nav_key của màn hình đều có nhà" do
    placed = sections.flat_map { |s| s[:items].map(&:first) } + [:scanner, :account]
    # Chỉ đọc trên CHÍNH dòng khai báo: quét nhiều dòng sẽ vớ phải mọi ký hiệu
    # khác trong file (params[:preset]...) và báo động giả.
    declared = Dir["app/controllers/merchant/*_controller.rb"].flat_map do |f|
      File.read(f).lines.grep(/def nav_key\b/).flat_map { |l| l.scan(/:(\w+)/).flatten }
    end.uniq.map(&:to_sym)
    assert_empty (declared - placed), "nav_key không thuộc mục nào: #{(declared - placed).inspect}"
  end

  test "máy quét vẫn có nút riêng, không nằm trong mục nào" do
    get merchant_root_path
    assert_select "a.l-nav-scan[href=?]", merchant_scanner_path, 1
    assert_not_includes sections.flat_map { |s| s[:items].map(&:first) }, :scanner
  end

  # Quản lý QR và máy quét dùng chung controller nhưng ở hai chỗ khác nhau.
  test "quản lý QR sáng ở mục Vận hành, không phải ở nút máy quét" do
    get merchant_scanner_checkin_qr_path
    assert_response :success
    ops = sections.find { |s| s[:key] == :operations }
    assert_includes ops[:items].map(&:first), :checkin_qr
  end
end
