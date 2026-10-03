require "test_helper"

# The merchant's "hiện đánh giá của khách khác" switch used to take the whole
# shop page with it: turn reviews off and the customer also lost the address,
# the opening hours, the amenities and the menu — a second decision nobody made.
class ShopPageVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "shopvis")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true,
                                             "amenities" => ["wifi"],
                                             "menu_highlights" => ["Cold Brew"]))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @outlet = @ws.outlets.first || Outlet.create!(workspace: @ws, name: "Thảo Điền", active: true)
      @outlet.update!(address: "12 Lê Lợi, Quận 1", phone: "0901234567",
                      settings: { "open_hours" => { "open" => "07:00", "close" => "22:00" } })
      @member = create(:member, workspace: @ws, email: "vis@example.com")
      @other  = create(:member, workspace: @ws, email: "other@example.com", name: "Người khác")
      @theirs = Rating.create!(workspace: @ws, member: @other, stars: 5, comment: "Cà phê ngon")
      @mine   = Rating.create!(workspace: @ws, member: @member, stars: 4, comment: "Chỗ ngồi thoải mái")
    end
    post "#{base}/login", params: { email: @member.email }
    post "#{base}/verify", params: {
      code: otp_code_for(@member.email, workspace: @ws)
    }
  end

  def base = "/w/#{@ws.slug}"

  def hide_reviews!
    @ws.update!(settings: @ws.settings.merge("feedback_public" => false))
  end

  test "the shop's own facts survive turning the public review list off" do
    hide_reviews!
    # The closing time is only printed while the shop is open, so pin the clock
    # rather than let this pass by day and fail overnight.
    travel_to Time.zone.local(2026, 10, 1, 10, 0) do
      get "#{base}/shop"
    end
    assert_response :success, "the shop page is not the review page"
    body = response.body
    assert_match @outlet.address, body
    assert_match "22:00", body, "opening hours"
    assert_match "Cold Brew", body, "menu highlights"
    assert_match I18n.t("merchant.amenities.wifi"), body
    assert_match I18n.t("customer.shop.call_shop"), body
  end

  test "with the switch off, other customers' reviews are the only thing gone" do
    hide_reviews!
    get "#{base}/shop"
    refute_match @theirs.comment, response.body, "someone else's review must not be shown"
    # ...but the member's own feedback, and the way to leave more, stay.
    assert_match @mine.comment, response.body
    assert_match I18n.t("customer.review.new_title"), response.body
  end

  test "with the switch on, the page reads exactly as the design draws it" do
    get "#{base}/shop"
    assert_match @theirs.comment, response.body
    assert_match @mine.comment, response.body
    assert_match @outlet.address, response.body
  end

  test "the way in is always on the home screen and in the profile" do
    hide_reviews!
    get base
    assert_select "a[href=?]", "#{base}/shop", { minimum: 1 }, "home should still link to the shop page"
    get "#{base}/me"
    assert_select "a[href=?]", "#{base}/shop", { minimum: 1 }, "the profile's help row should still link to it"
  end

  # Telling someone their words will be public when the shop has that turned
  # off is a promise the app does not keep.
  test "the review form says who will actually read it" do
    get "#{base}/review"
    assert_match I18n.t("customer.review.public_chip"), response.body

    hide_reviews!
    get "#{base}/review"
    assert_match I18n.t("customer.review.private_chip"), response.body
    refute_match I18n.t("customer.review.visibility_note", shop: @ws.name), response.body
  end
end
