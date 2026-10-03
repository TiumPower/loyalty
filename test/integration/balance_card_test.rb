require "test_helper"

# Khối điểm trên trang chủ: ảnh đại diện, tên và điểm trên MỘT hàng ngang, ghi
# chú thụt vào dưới tên. Hạng từng là một viên pill riêng đứng lẻ bên phải thẻ
# — hai hình viên thuốc cạnh nhau nói hai chuyện khác nhau.
class BalanceCardTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "bal", name: "Mộc Cà Phê")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws, tiers_enabled: true)
      @bronze = @ws.tiers.find_or_create_by!(key: "bronze") do |t|
        t.name = "Đồng"; t.threshold_points = 0; t.position = 0; t.multiplier = 1
      end
      @silver = @ws.tiers.find_or_create_by!(key: "silver") do |t|
        t.name = "Bạc"; t.threshold_points = 2000; t.position = 1; t.multiplier = 1.2
      end
      @member = create(:member, workspace: @ws, email: "bal@example.com", name: "Lê Quốc Viên")
      PointTransaction.create!(workspace: @ws, member: @member, kind: "earn", amount: 450)
      @member.recompute_points!
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: otp_code_for(@member.email, workspace: @ws)
    }
  end

  def base = "/w/#{@ws.slug}"

  test "tên và điểm nằm trên cùng một hàng" do
    get base
    assert_response :success
    # Vòng ảnh đại diện đã bỏ: khách chưa đặt được ảnh nên nó luôn chỉ là hai
    # chữ cái viết tắt, chiếm chỗ mà không nói thêm gì.
    assert_select ".l-balance .idrow .av", 0, "không còn vòng ảnh đại diện"
    assert_select ".l-balance .toprow .greet", /Viên/
    assert_select ".l-balance .toprow .l-ptspill .n", "450"
  end

  # Huy hiệu chỉ nói được RẰNG có hạng. Hạng nào thì phải đọc ra chữ — chủ quán
  # tự đặt tên hạng, nên không hình nào gợi được "Thành viên Bạch Kim".
  test "viên điểm ghi cả tên hạng, không chỉ có hình" do
    get base
    assert_response :success
    # "Hạng Đồng" chứ không trơ "Đồng": một mình cái tên đọc như một danh từ
    # bất kỳ, không nói được rằng đó là hạng thành viên.
    assert_select ".l-balance .l-ptspill .tier .tname", "Hạng Đồng"
    assert_select ".l-balance .l-ptspill .tier svg", 1, "tên hạng đi kèm huy hiệu chứ không thay nó"
  end

  # Tên hạng dài không được đẩy viên phình ngang: nó xếp DƯỚI huy hiệu.
  test "tên hạng dài bị cắt bằng ellipsis chứ không xuống dòng" do
    ActsAsTenant.with_tenant(@ws) { @bronze.update!(name: "Thành viên Bạch Kim Danh Dự") }
    get base
    assert_select ".l-balance .l-ptspill .tier .tname", "Hạng Thành viên Bạch Kim Danh Dự"
    css = File.read(Rails.root.join("app/assets/builds/tailwind.css"))
    rule = css[/\.l-ptspill \.tier \.tname\s*\{[^}]+\}/m]
    assert rule, "thiếu quy tắc cho tên hạng trong viên điểm"
    assert_includes rule, "text-overflow:ellipsis"
    assert_includes rule, "white-space:nowrap"
    # line-height 1 cộng overflow:hidden sẽ xén dấu tiếng Việt — "Đồng" thành "Đong".
    lh = rule[/line-height:\s*([0-9.]+)/, 1]
    assert lh && lh.to_f > 1.05, "line-height #{lh.inspect} quá chật, dấu tiếng Việt sẽ bị cắt"
  end

  # Huy hiệu hạng gộp vào viên điểm, không đứng thành viên thứ hai.
  test "hạng là huy hiệu trong viên điểm, không phải viên riêng" do
    get base
    assert_select ".l-balance .l-ptspill svg", { minimum: 1 }, "huy hiệu hạng nằm trong viên"
    assert_select ".l-balance > .l-pill.tier", 0, "không còn viên hạng rời bên ngoài"
  end

  test "viên điểm dẫn tới trang quyền lợi hạng" do
    get base
    assert_select ".l-balance a.l-ptspill[href=?]", "#{base}/tier", 1
  end

  # Không bật hạng thì viên vẫn còn, và dẫn về lịch sử điểm thay vì trang hạng.
  test "không có hạng thì viên dẫn về lịch sử điểm" do
    ActsAsTenant.with_tenant(@ws) { @ws.tiers.destroy_all; @member.update_columns(tier_key: nil) }
    get base
    assert_select ".l-balance a.l-ptspill[href=?]", "#{base}/history", 1
    assert_select ".l-balance .l-ptspill svg", 0
  end

  test "dòng dưới nói còn bao xa tới hạng kế" do
    get base
    assert_select ".l-balance .sub", /#{Regexp.escape(@silver.name)}/
    assert_select ".l-balance .l-bar", 1, "có thanh tiến độ"
  end

  # Điểm sắp hết hạn là thứ duy nhất ở đây có hạn chót, nên nó giành dòng dưới.
  test "điểm sắp hết hạn thay chỗ dòng hạng" do
    ActsAsTenant.with_tenant(@ws) do
      @ws.program.update!(points_expiry_months: 6)
      PointTransaction.where(member: @member).update_all(expires_at: 10.days.from_now)
    end
    get base
    assert_select ".l-balance .sub.expiring", 1
    assert_select ".l-balance .sub", { count: 1 }, "chỉ một dòng dưới, không chồng hai"
  end
end
