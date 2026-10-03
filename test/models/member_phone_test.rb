require "test_helper"

# Phone numbers are the login identifier now, so every spelling of the same
# number has to land on ONE account — otherwise a customer who types "+84…"
# today and "0…" tomorrow gets two profiles and loses their history.
class MemberPhoneTest < ActiveSupport::TestCase
  test "every spelling of one Vietnamese mobile canonicalises the same way" do
    [
      "0901234567",
      "090 123 4567",
      "090-123-4567",
      "+84901234567",
      "+84 90 123 45 67",
      "84901234567",
      "0084901234567"
    ].each do |typed|
      assert_equal "0901234567", Member.canonical_phone(typed), "failed for #{typed.inspect}"
    end
  end

  test "blank input is nil, not an empty string" do
    # An empty string would collide with every other blank under the unique
    # [workspace_id, phone] index; NULL does not.
    assert_nil Member.canonical_phone(nil)
    assert_nil Member.canonical_phone("")
    assert_nil Member.canonical_phone("   ")
    assert_nil Member.canonical_phone("abc")
  end

  test "an 11-digit local number is left alone" do
    assert_equal "02812345678", Member.canonical_phone("028 1234 5678")
  end

  test "the Zalo form is derived from the canonical one" do
    assert_equal "84901234567", PhoneFormat.vn84("090 123 4567")
    assert_equal "84901234567", PhoneFormat.vn84("+84901234567")
  end

  test "an unusable number has no Zalo form at all" do
    [nil, "", "abc", "12"].each { |junk| assert_nil PhoneFormat.vn84(junk) }
  end
end
