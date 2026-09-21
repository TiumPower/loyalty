require "tmpdir"

# Normalizes an AI-generated campaign banner to 16:9 and — when asked for —
# composites a real, scannable QR onto it, centered on a clean rounded white
# card, so the shared banner itself carries a working QR while keeping the nice
# illustrated look. Pass qr_url: nil for a banner without a QR.
#
# W/H match the AI image's native width (gpt-image 1536x1024 cropped to 16:9):
# downscaling to 1200 wide made the banner visibly soft on retina screens.
class BannerComposer
  W = 1536
  H = 864
  QR = 410        # QR pixel size
  PAD = 38        # white padding around the QR inside the card
  RADIUS = 32     # card corner radius

  def initialize(ai_bytes:, qr_url:)
    @ai_bytes = ai_bytes
    @qr_url = qr_url
  end

  # Returns PNG bytes (16:9, QR composited when a qr_url was given), or the
  # original AI bytes on any failure.
  def call
    require "mini_magick"
    card = QR + PAD * 2

    Dir.mktmpdir do |dir|
      qr_path     = File.join(dir, "qr.png")
      card_path   = File.join(dir, "card.png")
      carded_path = File.join(dir, "carded.png")
      bg_path     = File.join(dir, "bg.png")
      out_path    = File.join(dir, "out.png")

      # 0) Normalize the banner to 16:9 at full resolution.
      bg = MiniMagick::Image.read(@ai_bytes)
      bg.combine_options do |c|
        c.resize "#{W}x#{H}^"
        c.gravity "center"
        c.extent "#{W}x#{H}"
      end
      bg.write(bg_path)
      return File.binread(bg_path) if @qr_url.blank?

      # 1) QR PNG (small quiet zone; the card adds the visual padding).
      File.binwrite(qr_path, ApplicationController.helpers.qr_png(@qr_url, color: "1A1A1A", size: QR))

      # 2) Rounded white card canvas with a hairline border so it reads clearly
      #    as an overlaid card on top of a busy illustration.
      MiniMagick::Tool::Convert.new do |c|
        c.size "#{card}x#{card}"
        c << "xc:none"
        c.fill "white"
        c.stroke "rgba(0,0,0,0.10)"
        c.strokewidth "3"
        c.draw "roundrectangle 1,1,#{card - 2},#{card - 2},#{RADIUS},#{RADIUS}"
        c << card_path
      end

      # 3) QR centered on the card.
      MiniMagick::Tool::Composite.new do |c|
        c.gravity "center"
        c << qr_path
        c << card_path
        c << carded_path
      end

      # 4) Composite the card centered in the right half of the banner.
      MiniMagick::Tool::Composite.new do |c|
        c.gravity "East"
        c.geometry "+#{(W * 0.125).round}+0"
        c << carded_path
        c << bg_path
        c << out_path
      end

      File.binread(out_path)
    end
  rescue => e
    Rails.logger.error("[BannerComposer] #{e.class}: #{e.message}")
    @ai_bytes
  end
end
