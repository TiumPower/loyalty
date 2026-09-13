require "test_helper"

# White-label: a shop with no uploaded logo must still be branded as itself,
# never as the platform.
class ShopIconTest < ActionDispatch::IntegrationTest
  setup { @ws = create(:workspace, name: "Quán Nhỏ", subdomain: "iconsmoke") }

  test "renders an SVG from the shop's initials" do
    get "/w/#{@ws.slug}/shop-icon.svg"
    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_match "QN", response.body
    assert_match @ws.theme_value("primary"), response.body
  end

  test "renders a PNG for home-screen icons" do
    get "/w/#{@ws.slug}/shop-icon-192.png"
    assert_includes [200, 302], response.status
  end

  test "the manifest points at the shop's own icon, not the platform's" do
    get "/w/#{@ws.slug}/manifest.webmanifest"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Quán Nhỏ", body["name"]
    assert body["icons"].none? { |i| i["src"] == "/icon.png" }, "still falling back to the platform icon"
    assert body["icons"].any? { |i| i["purpose"] == "maskable" }
  end
end
