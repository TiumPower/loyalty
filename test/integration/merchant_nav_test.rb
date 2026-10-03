require "test_helper"

# Thanh menu merchant. Mục "Vận hành" chỉ có hai màn, mà máy quét đã có nút
# riêng nổi bật ngay phía trên — nên nó chỉ là một lớp phải bấm qua để tới
# Giao dịch.
class MerchantNavTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @ws = create(:workspace, subdomain: "nav")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: @user, workspace: @ws, role: "owner") }
    sign_in @user
  end

  test "menu không còn mục Vận hành" do
    get merchant_root_path
    assert_response :success
    keys = ActsAsTenant.with_tenant(@ws) { @controller.view_context.merchant_sections.map { |s| s[:key] } }
    assert_not_includes keys, :operations
  end

  # Gỡ một mục khỏi menu không được làm mồ côi màn hình nào bên trong nó.
  test "Giao dịch vẫn tới được, từ Tổng quan" do
    get merchant_root_path
    assert_select "a[href=?]", merchant_transactions_path, { minimum: 1 },
                  "Tổng quan phải có tab dẫn sang Giao dịch"
    get merchant_transactions_path
    assert_response :success
  end

  test "máy quét vẫn có nút riêng trên menu" do
    get merchant_root_path
    assert_select "a.l-nav-scan[href=?]", merchant_scanner_path, 1
    get merchant_scanner_path
    assert_response :success
  end
end
