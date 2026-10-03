require "test_helper"
require "yaml"

# Hai file ngôn ngữ dài hơn hai nghìn dòng, và YAML khi gặp khoá TRÙNG trong
# cùng một khối thì lặng lẽ lấy bản sau — bản trước thành chữ chết mà không ai
# biết. Đã vấp thật: `customer.home.greeting_morning` tồn tại sẵn, một lần sửa
# sau thêm bản thứ hai vào đúng khối đó, và chuỗi cũ biến mất không dấu vết.
class LocaleFilesTest < ActiveSupport::TestCase
  LOCALES = %w[vi en].freeze

  test "không file ngôn ngữ nào có khoá trùng" do
    LOCALES.each do |locale|
      dupes = duplicate_keys(Rails.root.join("config/locales/#{locale}.yml"))
      assert_empty dupes, "#{locale}.yml có khoá trùng: #{dupes.join(', ')}"
    end
  end

  # Thiếu một khoá ở một ngôn ngữ không làm test đỏ (fallback che mất), nên phải
  # so hai bên với nhau.
  #
  # Chỉ so các namespace của CHÍNH app: `date`, `time`, `datetime`,
  # `activerecord`… là của Rails, và vi.yml cố ý ghi đè một phần trong khi en
  # dùng nguyên bản gốc — chênh lệch ở đó là đúng, không phải thiếu sót.
  OURS = %w[customer merchant admin].freeze

  test "hai ngôn ngữ có cùng bộ khoá ở các phần của app" do
    vi = app_keys("vi")
    en = app_keys("en")
    assert_empty (vi - en), "có ở vi nhưng thiếu ở en"
    assert_empty (en - vi), "có ở en nhưng thiếu ở vi"
  end

  private

  # Psych không báo khoá trùng, nên quét thô theo thụt lề: trong cùng một khối
  # (cùng mức thụt), một tên khoá chỉ được xuất hiện một lần.
  def duplicate_keys(path)
    seen = Hash.new { |h, k| h[k] = {} }
    dupes = []
    File.readlines(path).each do |line|
      next if line.strip.empty? || line.strip.start_with?("#")
      m = line.match(/\A(\s*)([a-z0-9_]+):/i) or next
      indent, key = m[1].length, m[2]
      seen.each_key { |lvl| seen.delete(lvl) if lvl > indent }
      path_key = "#{indent}/#{key}"
      dupes << key if seen[indent][key]
      seen[indent][key] = true
    end
    dupes.uniq
  end

  def app_keys(locale)
    root = YAML.load_file(Rails.root.join("config/locales/#{locale}.yml"))[locale]
    OURS.flat_map { |ns| root[ns] ? flatten(root[ns], ns) : [] }
  end

  def flatten(hash, prefix = nil, out = [])
    hash.each do |key, value|
      full = [prefix, key].compact.join(".")
      value.is_a?(Hash) ? flatten(value, full, out) : out << full
    end
    out
  end
end
