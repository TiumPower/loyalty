require "test_helper"

# Opening hours, amenities and menu highlights: the three things the design's
# shop page shows that the app had no home for.
class ShopProfileTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "profileshop")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @outlet = @ws.outlets.first || Outlet.create!(workspace: @ws, name: "Chi nhánh 1", active: true)
    end
    sign_in @user
  end

  test "a branch records its opening hours" do
    patch "/merchant/outlets/#{@outlet.id}",
          params: { outlet: { name: @outlet.name, open_hours: { open: "07:00", close: "22:00" } } }
    @outlet.reload
    assert_equal "07:00", @outlet.opens_at
    assert_equal "22:00", @outlet.closes_at
  end

  # A branch with no hours must show no "open now" badge at all — the badge used
  # to be a constant that claimed the shop was open at any hour.
  test "no hours means no claim either way" do
    assert_nil @outlet.open_at?
    assert_not @outlet.hours?
  end

  test "hours that are not times are refused, and nothing is written" do
    patch "/merchant/outlets/#{@outlet.id}",
          params: { outlet: { name: @outlet.name, open_hours: { open: "sáng sớm", close: "22:00" } } }
    assert_response :unprocessable_entity
    assert_not @outlet.reload.hours?, "a rejected save must not leave half the hours behind"
    assert_not Outlet.new(workspace: @ws, name: "x",
                          settings: { "open_hours" => { "open" => "25:00", "close" => "9" } }).valid?
  end

  test "clearing the hours removes them" do
    @outlet.update!(settings: { "open_hours" => { "open" => "07:00", "close" => "22:00" } })
    patch "/merchant/outlets/#{@outlet.id}",
          params: { outlet: { name: @outlet.name, open_hours: { open: "", close: "" } } }
    assert_not @outlet.reload.hours?
  end

  test "amenities and menu highlights are saved, and junk is dropped" do
    patch "/merchant/appearance", params: {
      name: @ws.name,
      amenities: ["wifi", "takeaway", "not-a-real-amenity"],
      menu_highlights: "Cà phê sữa đá, Cold Brew, Cà phê sữa đá, ,"
    }
    @ws.reload
    assert_equal %w[wifi takeaway], @ws.amenity_list
    assert_equal ["Cà phê sữa đá", "Cold Brew"], @ws.menu_highlights
  end

  # Unticking every chip has to post an empty list, or the last amenity could
  # never be removed.
  test "unticking every amenity clears them" do
    @ws.update!(settings: @ws.settings.merge("amenities" => %w[wifi]))
    patch "/merchant/appearance", params: { name: @ws.name, amenities: [""] }
    assert_empty @ws.reload.amenity_list
  end

  test "the customer shop page shows all three" do
    ActsAsTenant.with_tenant(@ws) do
      @ws.update!(settings: @ws.settings.merge("feedback_public" => true))
      @ws.amenities = %w[wifi]
      @ws.menu_highlights = "Cold Brew"
      @ws.save!
      @outlet.update!(settings: { "open_hours" => { "open" => "07:00", "close" => "22:00" } })
      member = create(:member, workspace: @ws)
      post "/w/#{@ws.slug}/login", params: { email: member.email }
      post "/w/#{@ws.slug}/verify", params: { code: OtpChallenge.order(:created_at).last.code }
    end
    get "/w/#{@ws.slug}/shop"
    assert_response :success
    assert_match "Cold Brew", response.body
    assert_match I18n.t("merchant.amenities.wifi"), response.body
    assert_match "22:00", response.body
  end
end
