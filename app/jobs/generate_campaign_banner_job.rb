class GenerateCampaignBannerJob < ApplicationJob
  queue_as :default

  def perform(campaign_id)
    campaign = Campaign.find_by(id: campaign_id) or return
    ActsAsTenant.with_tenant(campaign.workspace) do
      result = AiImageService.safe_call(fallback: nil) do
        AiImageService.new.generate(banner_prompt(campaign))
      end
      if result.nil? # no key / error → merchant can upload manually
        campaign.update_columns(banner_status: "failed", updated_at: Time.current)
        return
      end

      # Composite the real scannable QR onto the banner (keeps the nice look
      # while the code actually works). Falls back to the plain image on error.
      bytes = result[:bytes]
      if (scan_url = promo_scan_url(campaign))
        bytes = BannerComposer.new(ai_bytes: bytes, qr_url: scan_url).call
      end

      campaign.banner.attach(io: StringIO.new(bytes),
                             filename: "banner-#{campaign.id}.png",
                             content_type: "image/png")
      campaign.update_columns(banner_status: "ready", updated_at: Time.current)
    end
  rescue => e
    Rails.logger.error("[GenerateCampaignBannerJob] #{e.class}: #{e.message}")
    campaign&.update_columns(banner_status: "failed", updated_at: Time.current)
  end

  private

  # Absolute scan URL the composited QR should encode (nil when no usable promo).
  # A campaign that has not started yet still has a dormant QR: its code goes
  # live the moment the merchant presses start, so composite it now — otherwise
  # a banner generated from the create form would carry no QR at all.
  def promo_scan_url(campaign)
    promo = campaign.promo_codes.where(active: true).first
    promo ||= campaign.promo_codes.first if %w[draft scheduled].include?(campaign.status)
    return nil if promo.nil?
    ws = campaign.workspace
    host = ws.custom_domain.presence || "#{ws.subdomain}.#{ApplicationController::PLATFORM_HOST}"
    "https://#{host}/scan/resolve?promo=#{promo.token}"
  end

  def banner_prompt(c)
    theme = c.workspace.resolved_theme
    title = c.content_value("title").presence || c.name
    body  = c.content_value("body").to_s
    industry = { "fnb" => "cà phê / đồ ăn thức uống", "retail" => "cửa hàng bán lẻ", "service" => "dịch vụ" }[c.workspace.industry] || "cửa hàng"
    offer = if c.reward
      "The offer is a #{c.reward.kind} — \"#{c.reward.title}\" (#{c.reward.value_label}); evoke this gift/discount visually (e.g. a gift box, a voucher tag/ribbon, a discount ribbon, the product itself)."
    else
      "Evoke a general reward/gift vibe (gift box, ribbon)."
    end
    <<~PROMPT
      A warm, inviting flat-vector promotional banner (16:9) for a #{industry}
      loyalty campaign. Theme: "#{title}"#{body.present? ? " — #{body}" : ''} (#{c.type_label}).
      #{offer}
      Charming, polished illustration whose rich decorative elements (cups, treats,
      gifts, envelopes, ribbons, leaves) COVER THE ENTIRE CANVAS EVENLY, edge to
      edge, including the full RIGHT side. Distribute the imagery across the whole
      width — do NOT cluster everything on the left.
      ABSOLUTELY NO blank, empty, plain, or lightly-tinted rectangular areas, and
      NO card / label / tag / plaque / frame / paper / envelope-panel shape left
      empty for text. Every part of the image must be filled with illustration.
      Palette built around #{theme['primary']} and #{theme['primary_2']}.
      IMPORTANT: do NOT render ANY text, letters, words, numbers, logos, QR codes,
      barcodes, or phone screens with codes — a real QR card is composited by the
      system afterwards, so keep the image completely text-free.
    PROMPT
  end
end
