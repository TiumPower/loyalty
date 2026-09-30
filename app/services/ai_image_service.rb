# Thin OpenAI Images client for generating campaign banners. Anthropic's API
# can't generate images, so this uses OpenAI's Images API (gpt-image-1). Reads
# ENV["OPENAI_API_KEY"]; when missing the service is not `configured?` and
# callers fall back to the manual-upload / gradient placeholder path.
class AiImageService
  API_URL = "https://api.openai.com/v1/images/generations"
  MODEL   = "gpt-image-2"

  class Error < StandardError; end

  def self.configured? = ENV["OPENAI_API_KEY"].to_s.strip.present?

  # Run defensively: returns the block value or `fallback` on missing key / error.
  def self.safe_call(fallback: nil)
    return fallback unless configured?
    yield
  rescue Error => e
    Rails.logger.error("[AiImageService] #{e.message}")
    fallback
  end

  def initialize(size: "1536x1024")
    @size = size
  end

  # Returns { bytes:, content_type: } for a generated PNG, or raises Error.
  def generate(prompt)
    raise Error, "OPENAI_API_KEY missing" unless self.class.configured?
    resp = connection.post(API_URL) do |req|
      req.headers["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
      req.headers["content-type"] = "application/json"
      req.body = { model: MODEL, prompt: prompt, size: @size, n: 1 }.to_json
    end
    unless resp.success?
      raise Error, "OpenAI Images #{resp.status}: #{resp.body.to_s.truncate(300)}"
    end
    data = JSON.parse(resp.body)
    b64 = data.dig("data", 0, "b64_json")
    raise Error, "OpenAI Images: no image in response" if b64.blank?
    { bytes: Base64.decode64(b64), content_type: "image/png" }
  rescue Faraday::Error => e
    raise Error, "OpenAI Images network error: #{e.message}"
  end

  private

  def connection
    @connection ||= Faraday.new do |f|
      f.request :retry, max: 1, interval: 1.0, retry_statuses: [ 429, 500, 502, 503 ]
      f.options.timeout = 120
      f.options.open_timeout = 10
    end
  end
end
