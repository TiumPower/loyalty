require "test_helper"

# The banner is the one image merchants post publicly, so it has to come out at
# full 16:9 resolution — a downscaled one looked soft on phones.
class BannerComposerTest < ActiveSupport::TestCase
  setup do
    # A plain 2000x1200 source, i.e. wider than 16:9, so cropping is exercised.
    require "mini_magick"
    @bytes = begin
      Dir.mktmpdir do |dir|
        path = File.join(dir, "src.png")
        MiniMagick::Tool::Convert.new do |c|
          c.size "2000x1200"
          c << "xc:#c98a3c"
          c << path
        end
        File.binread(path)
      end
    end
  end

  def dimensions(bytes)
    img = MiniMagick::Image.read(bytes)
    [img.width, img.height]
  end

  test "a banner without a QR is still normalized to full-resolution 16:9" do
    out = BannerComposer.new(ai_bytes: @bytes, qr_url: nil).call
    assert_equal [BannerComposer::W, BannerComposer::H], dimensions(out)
    assert_equal [1536, 864], dimensions(out) # guards against a silent downscale
  end

  test "a banner with a QR keeps the same dimensions" do
    out = BannerComposer.new(ai_bytes: @bytes, qr_url: "https://example.com/scan/resolve?promo=abc").call
    assert_equal [BannerComposer::W, BannerComposer::H], dimensions(out)
    # The composited QR card makes the image differ from the plain one.
    assert_not_equal BannerComposer.new(ai_bytes: @bytes, qr_url: nil).call, out
  end
end
