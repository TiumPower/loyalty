require "test_helper"

# Theme tokens are rendered straight into a <style> block and the logo is shown
# to every customer, including as their home-screen icon.
class BrandingTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "brand")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: @user, workspace: @ws, role: "owner") }
    sign_in @user
  end

  test "a hex colour is saved" do
    patch "/merchant/appearance", params: { theme: { primary: "#123ABC" } }
    assert_equal "#123ABC", @ws.reload.theme_value(:primary)
  end

  test "a value that is not a colour is refused with a reason" do
    patch "/merchant/appearance", params: { theme: { primary: "red; } body{display:none} x{a:b" } }
    assert_response :unprocessable_entity
    assert_match(/Màu không hợp lệ/, response.body)
  end

  test "a colour already stored badly never reaches the stylesheet" do
    @ws.update_columns(theme: { "primary" => "red; } body{display:none}" })
    assert_equal Workspace::DEFAULT_THEME["primary"], @ws.reload.theme_value(:primary)
  end

  test "a preset applies a full palette" do
    patch "/merchant/appearance", params: { preset: "modern_beauty" }
    assert_equal "#C64B8C", @ws.reload.theme_value(:primary)
  end

  test "a non-image cannot be used as the logo" do
    Tempfile.create(["x", ".pdf"]) do |f|
      f.write("%PDF-1.4 not really")
      f.rewind
      patch "/merchant/appearance",
            params: { logo: Rack::Test::UploadedFile.new(f.path, "application/pdf") }
    end
    assert_not @ws.reload.logo.attached?, "a PDF was accepted as the shop's logo"
    assert_response :unprocessable_entity
  end

  test "an oversized image is refused" do
    Tempfile.create(["big", ".png"]) do |f|
      f.binmode
      f.write("\x89PNG\r\n\x1a\n".b + ("0" * (Workspace::LOGO_MAX_BYTES + 1024)))
      f.rewind
      patch "/merchant/appearance",
            params: { logo: Rack::Test::UploadedFile.new(f.path, "image/png") }
    end
    assert_not @ws.reload.logo.attached?, "an oversized logo was accepted"
  end

  test "a cashier cannot change the branding" do
    ActsAsTenant.with_tenant(@ws) { Membership.find_by(user: @user).update!(role: "cashier") }
    patch "/merchant/appearance", params: { theme: { primary: "#000000" } }
    assert_not_equal "#000000", @ws.reload.theme_value(:primary)
  end
end

# custom_domain is resolved BEFORE the subdomain, so a bad value has reach.
class CustomDomainTest < ActiveSupport::TestCase
  def build(domain)
    ActsAsTenant.without_tenant do
      Workspace.new(name: "T", subdomain: "dtest", industry: "fnb", custom_domain: domain)
    end
  end

  test "the platform's own host cannot be claimed" do
    w = build(Workspace.platform_host)
    assert_not w.valid?
    assert w.errors[:custom_domain].any?
  end

  test "a shop subdomain of the platform cannot be claimed" do
    w = build("cozycafe.#{Workspace.platform_host}")
    assert_not w.valid?
  end

  test "a real domain is accepted and normalised" do
    w = build("  HTTPS://Loyalty.TenShop.vn/  ")
    w.valid?
    assert_equal "loyalty.tenshop.vn", w.custom_domain
    assert_empty w.errors[:custom_domain]
  end

  test "something that is not a hostname is refused" do
    w = build("not a domain")
    assert_not w.valid?
  end

  test "no custom domain at all is fine" do
    w = build(nil)
    w.valid?
    assert_empty w.errors[:custom_domain]
  end
end
