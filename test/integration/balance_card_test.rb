require "test_helper"

# Khối "Điểm hiện có". Hạng từng là một viên pill riêng đứng lẻ bên phải thẻ —
# hai hình viên thuốc cạnh nhau nói hai chuyện khác nhau. Giờ hạng là nửa sau
# của cùng một viên.
class BalanceCardTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "bal", name: "Mộc Cà Phê")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, tiers_enabled: true)
      @tier = @ws.tiers.find_or_create_by!(key: "bronze") do |t|
        t.name = "Đồng"; t.threshold_points = 0; t.position = 0; t.multiplier = 1
      end
      @member = create(:member, workspace: @ws, email: "bal@example.com", name: "Lê Quốc Viên")
      PointTransaction.create!(workspace: @ws, member: @member, kind: "earn", amount: 1250)
      @member.recompute_points!
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email).order(:id).last.code
    }
  end

  def base = "/w/#{@ws.slug}"

  test "lời chào có tên khách, rồi mới tới nhãn điểm" do
    get base
    assert_response :success
    assert_select ".l-balance .greet", /Viên/
    assert_select ".l-balance .lbl", I18n.t("customer.home.points_balance")
  end

  test "điểm và hạng nằm trong cùng một viên" do
    get base
    assert_select ".l-balance .l-ptspill .n", "1.250"
    assert_select ".l-balance .l-ptspill a.tier", 1
    assert_select ".l-balance .l-ptspill a.tier", /#{Regexp.escape(@tier.name)}/
  end

  # Viên hạng rời bên phải thẻ không được còn nữa, nếu không lại thành hai viên.
  test "không còn viên hạng riêng bên ngoài" do
    get base
    assert_select ".l-balance > .l-pill.tier", 0
  end

  test "hạng vẫn dẫn tới trang quyền lợi hạng" do
    get base
    assert_select ".l-balance .l-ptspill a.tier[href=?]", "#{base}/tier"
  end

  # Chương trình không bật hạng thì viên chỉ còn số điểm, không để hở một bên.
  test "không có hạng thì viên vẫn cân" do
    ActsAsTenant.with_tenant(@ws) { @ws.tiers.destroy_all; @member.update_columns(tier_key: nil) }
    get base
    assert_select ".l-balance .l-ptspill", 1
    assert_select ".l-balance .l-ptspill a.tier", 0
  end
end
