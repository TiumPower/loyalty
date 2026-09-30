require "test_helper"
require "minitest/mock"

# Coordinates behind the customer app's "0.5 km away".
class OutletGeocodingTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "geo")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @outlet = @ws.outlets.first || Outlet.create!(workspace: @ws, name: "Chi nhánh 1", active: true)
      @outlet.update_columns(address: "12 Nguyễn Ư Dĩ, Thảo Điền, TP. Thủ Đức",
                             latitude: nil, longitude: nil, geocode_manual: false)
    end
    sign_in @user
  end

  # A single address line is split into the parts the lookup wants: the last
  # comma-separated piece is the city, the one before it the district.
  test "an address line is split into street, ward, district and city" do
    seen = nil
    GeocoderService.stub(:lookup, ->(**kw) { seen = kw; nil }) do
      GeocoderService.lookup_line("12 Nguyễn Ư Dĩ, Thảo Điền, TP. Thủ Đức")
    end
    assert_equal "12 Nguyễn Ư Dĩ", seen[:address_line]
    assert_equal "Thảo Điền", seen[:district]
    assert_equal "TP. Thủ Đức", seen[:city]
  end

  test "an address with no commas is still looked up" do
    seen = nil
    GeocoderService.stub(:lookup, ->(**kw) { seen = kw; nil }) do
      GeocoderService.lookup_line("Chợ Bến Thành")
    end
    assert_equal "Chợ Bến Thành", seen[:address_line]
  end

  test "saving a new address queues a lookup" do
    assert_enqueued_with(job: GeocodeOutletJob) do
      @outlet.update!(address: "45 Lý Tự Trọng, Bến Nghé, Quận 1")
    end
  end

  # Typing a coordinate is a correction. The next address edit must not undo it.
  test "coordinates typed by hand are never overwritten" do
    patch "/merchant/outlets/#{@outlet.id}",
          params: { outlet: { name: @outlet.name, address: @outlet.address,
                              latitude: "10.8012", longitude: "106.7360" } }
    @outlet.reload
    assert @outlet.geocode_manual?, "typing a coordinate should claim it"
    assert_equal 10.8012, @outlet.latitude.to_f

    assert_no_enqueued_jobs(only: GeocodeOutletJob) do
      @outlet.update!(address: "Địa chỉ mới, Quận 3, Hồ Chí Minh")
    end
    assert_equal 10.8012, @outlet.reload.latitude.to_f
  end

  test "handing the pin back re-enables the automatic lookup" do
    @outlet.update_columns(geocode_manual: true, latitude: 10.8, longitude: 106.7)
    assert_enqueued_with(job: GeocodeOutletJob) do
      patch "/merchant/outlets/#{@outlet.id}",
            params: { outlet: { name: @outlet.name, address: @outlet.address }, reset_geocode: "1" }
    end
    @outlet.reload
    assert_not @outlet.geocode_manual?
    assert_nil @outlet.latitude
  end

  # The "tự lấy toạ độ" button: the merchant edits the address and asks for the
  # answer there and then, instead of saving and hoping the background job has
  # caught up by the time they look again.
  test "the lookup button answers with coordinates and says how precise they are" do
    hit = GeocoderService::Result.new(lat: 16.0689577, lon: 108.2174048,
                                      display_name: "Ngô Gia Tự, Hải Châu, Đà Nẵng",
                                      precision: "street")
    GeocoderService.stub(:lookup_line, hit) do
      post "/merchant/outlets/geocode", params: { address: "10 Ngô Gia Tự, Hải Châu, Đà Nẵng" }
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert body["ok"]
    assert_equal 16.0689577, body["lat"]
    assert_equal 108.2174048, body["lon"]
    assert_equal I18n.t("merchant.outlets.geo_exact"), body["note"]
    assert_match "Đà Nẵng", body["label"]
  end

  test "a district-level answer says so rather than posing as the door" do
    hit = GeocoderService::Result.new(lat: 16.06, lon: 108.21, display_name: "Hải Châu", precision: "district")
    GeocoderService.stub(:lookup_line, hit) do
      post "/merchant/outlets/geocode", params: { address: "Hải Châu, Đà Nẵng" }
    end
    assert_equal I18n.t("merchant.outlets.geo_approx"), JSON.parse(response.body)["note"]
  end

  test "the lookup writes nothing and reports an address the map does not know" do
    before = [@outlet.latitude, @outlet.longitude, @outlet.geocoded_at]
    GeocoderService.stub(:lookup_line, nil) do
      post "/merchant/outlets/geocode", params: { address: "Không có thật, Nơi Nào Đó" }
    end
    body = JSON.parse(response.body)
    assert_not body["ok"]
    assert_equal I18n.t("merchant.outlets.geo_not_found"), body["error"]
    assert_equal before, [@outlet.reload.latitude, @outlet.longitude, @outlet.geocoded_at]
  end

  test "an empty address is refused before Nominatim is troubled" do
    called = false
    GeocoderService.stub(:lookup_line, ->(*) { called = true; nil }) do
      post "/merchant/outlets/geocode", params: { address: "   " }
    end
    assert_not JSON.parse(response.body)["ok"]
    assert_not called, "no address, no request"
  end

  # The button's answer IS the automatic answer, just asked for by hand. Saving
  # it must not freeze the branch against the next address edit the way typing
  # a coordinate does.
  test "a coordinate from the button stays automatic" do
    patch "/merchant/outlets/#{@outlet.id}",
          params: { outlet: { name: @outlet.name, address: @outlet.address,
                              latitude: "16.0689577", longitude: "108.2174048" },
                    coords_source: "lookup" }
    @outlet.reload
    assert_not @outlet.geocode_manual?, "the button is not the keyboard"
    assert_equal 16.0689577, @outlet.latitude.to_f
    assert @outlet.geocoded_at.present?

    assert_enqueued_with(job: GeocodeOutletJob) do
      @outlet.update!(address: "45 Lý Tự Trọng, Bến Nghé, Quận 1")
    end
  end

  # Only a manager may spend the shop's Nominatim budget.
  test "a cashier cannot use the lookup" do
    sign_out @user
    cashier = create(:user)
    ActsAsTenant.with_tenant(@ws) { Membership.create!(user: cashier, workspace: @ws, role: "staff") }
    sign_in cashier
    post "/merchant/outlets/geocode", params: { address: "10 Ngô Gia Tự, Đà Nẵng" }
    assert_redirected_to merchant_root_path
  end

  test "a branch with no coordinates offers no distance" do
    assert_not @outlet.located?
    assert_nil @outlet.coords
  end

  test "nonsense coordinates are refused" do
    @outlet.latitude = 999
    assert_not @outlet.valid?
  end
end
