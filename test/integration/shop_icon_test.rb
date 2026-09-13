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

  # The SVG looked right in a browser while the rasterised PNG — the one that
  # actually lands on a phone's home screen — came out solid black, because
  # ImageMagick's SVG renderer ignores fill="url(#gradient)". Assert on the
  # pixels, not on the markup.
  test "the rasterised icon is the shop's colour, not black" do
    get "/w/#{@ws.slug}/shop-icon-192.png"
    skip "rasterizer unavailable here" unless response.status == 200 && response.media_type == "image/png"

    require "mini_magick"
    Tempfile.create(["icon", ".png"]) do |f|
      f.binmode
      f.write(response.body)
      f.flush
      corner = MiniMagick::Image.open(f.path).get_pixels[8][8] # inside the tile
      assert corner.sum > 60, "icon rendered near-black (#{corner.inspect})"
    end
  rescue LoadError
    skip "mini_magick unavailable"
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
