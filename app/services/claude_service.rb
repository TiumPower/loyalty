# Thin Claude (Anthropic) client for Loyalty's AI features:
#   - text generation  (campaign copy, colour suggestions)
#   - JSON generation  (structured colour palettes)
#   - vision           (verify a Google-review screenshot for a mission)
#
# Reads ENV["ANTHROPIC_API_KEY"] (dev: .env, prod: shared/.env). If the key is
# missing the service is simply not `configured?` and callers fall back to a
# non-AI path, so the app keeps working without a key.
class ClaudeService
  API_URL = "https://api.anthropic.com/v1/messages"
  API_VERSION = "2023-06-01"

  HAIKU  = "claude-haiku-4-5-20251001" # cheap + fast + vision
  SONNET = "claude-sonnet-5"           # better copy/reasoning
  OPUS   = "claude-opus-4-8"           # most capable — used for every AI task here

  # Models that reject the `temperature` param (newer models deprecated it).
  NO_TEMPERATURE = [ SONNET, OPUS ].freeze

  class Error < StandardError; end

  def self.configured? = ENV["ANTHROPIC_API_KEY"].to_s.strip.present?

  # Run an AI call defensively: returns the block's value, or `fallback` (nil by
  # default) when the key is missing or Claude errors out. Every AI feature is
  # optional — a failure must degrade to the manual/default path, never 500.
  def self.safe_call(fallback: nil)
    return fallback unless configured?
    yield
  rescue Error => e
    Rails.logger.error("[ClaudeService] #{e.message}")
    fallback
  end

  def initialize(model: HAIKU, max_tokens: 1024, temperature: 0.7)
    @model = model
    @max_tokens = max_tokens
    @temperature = temperature
  end

  # Returns the assistant's text. `content` may be a String or an array of
  # Anthropic content blocks (for vision).
  def text(content, system: nil)
    body = {
      model: @model, max_tokens: @max_tokens,
      messages: [ { role: "user", content: content } ]
    }
    # Some models deprecated `temperature` and 400 if it's sent.
    body[:temperature] = @temperature if @temperature && NO_TEMPERATURE.exclude?(@model)
    body[:system] = system if system.present?
    resp = post(body)
    Array(resp["content"]).map { |b| b["text"] }.compact.join.strip
  end

  # Returns a parsed Hash/Array. Asks the model for JSON and salvages the first
  # {...} / [...] block if it wraps the answer in prose.
  def json(prompt, system: nil)
    raw = text(prompt, system: [ system, "Chỉ trả về JSON hợp lệ, không giải thích." ].compact.join("\n"))
    parse_json(raw)
  end

  # Vision helper: prompt + one image (raw bytes + media type e.g. "image/jpeg").
  def vision_json(prompt, image_bytes:, media_type:, system: nil)
    content = [
      { type: "image", source: { type: "base64", media_type: media_type,
                                 data: Base64.strict_encode64(image_bytes) } },
      { type: "text", text: prompt }
    ]
    raw = text(content, system: [ system, "Chỉ trả về JSON hợp lệ, không giải thích." ].compact.join("\n"))
    parse_json(raw)
  end

  private

  def post(body)
    raise Error, "ANTHROPIC_API_KEY missing" unless self.class.configured?
    resp = connection.post(API_URL) do |req|
      req.headers["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
      req.headers["anthropic-version"] = API_VERSION
      req.headers["content-type"] = "application/json"
      req.body = body.to_json
    end
    unless resp.success?
      raise Error, "Claude API #{resp.status}: #{resp.body.to_s.truncate(300)}"
    end
    JSON.parse(resp.body)
  rescue Faraday::Error => e
    raise Error, "Claude API network error: #{e.message}"
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.request :retry, max: 2, interval: 0.5, backoff_factor: 2,
                        retry_statuses: [ 429, 500, 502, 503, 529 ]
      f.options.timeout = 60
      f.options.open_timeout = 10
    end
  end

  def parse_json(raw)
    # Strip ```json … ``` code fences the model sometimes wraps around the JSON.
    cleaned = raw.to_s.sub(/\A\s*```(?:json)?\s*/i, "").sub(/\s*```\s*\z/, "")
    JSON.parse(cleaned)
  rescue JSON::ParserError
    if (m = cleaned.match(/\{.*\}/m) || cleaned.match(/\[.*\]/m))
      JSON.parse(m[0]) rescue {}
    else
      {}
    end
  end
end
