require "test_helper"

# The customer inbox. Everything the shop sends lands here, and the shop sends
# one row per member per broadcast — so it both has to stay readable and has to
# stop growing forever.
class CustomerNotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "notifws")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @member = create(:member, workspace: @ws, email: "inbox@example.com")
    end
    sign_in_member!
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member!
    post "#{base}/login", params: { email: @member.email }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email, purpose: "login").order(:id).last
    post "#{base}/verify", params: { code: ch.code }
  end

  def notify!(n, member: @member, read: false, at: Time.current)
    ActsAsTenant.with_tenant(@ws) do
      Notification.create!(workspace: @ws, member: member, kind: "promo",
                           title: "Tin #{n}", body: "Nội dung #{n}",
                           read_at: (read ? at : nil), created_at: at, updated_at: at)
    end
  end

  # Opening the inbox marked EVERY unread row read, while rendering only the
  # newest fifty. Anything past that was marked read without ever being shown,
  # and with no way to page back it could never be shown again.
  test "opening the inbox only marks what it actually showed" do
    older = (1..70).map { |i| notify!(i, at: i.hours.ago) }

    get "#{base}/notifications"
    assert_response :success

    shown = older.first(Customer::NotificationsController::PER)
    hidden = older.drop(Customer::NotificationsController::PER)
    assert shown.all? { |n| n.reload.read? }, "what was on screen is read"
    assert hidden.none? { |n| n.reload.read? }, "what was never shown stays unread"
  end

  # With a hard limit and no pager, older notifications were simply gone.
  test "older notifications can be paged back to" do
    (1..70).each { |i| notify!(i, at: i.hours.ago) }

    get "#{base}/notifications"
    assert_response :success
    assert_match "Tin 1", response.body
    refute_match(/Tin 70\b/, response.body)
    assert_select "a[href=?]", "#{base}/notifications?page=2"

    get "#{base}/notifications?page=2"
    assert_response :success
    assert_match(/Tin 70\b/, response.body)
  end

  test "read_all still clears the badge" do
    3.times { |i| notify!(i) }
    post "#{base}/notifications/read_all"
    assert_redirected_to "#{base}/notifications"
    ActsAsTenant.with_tenant(@ws) { assert_equal 0, @member.notifications.unread.count }
  end

  # One row per member per broadcast, kept forever: a shop with a few thousand
  # members writes six figures of rows a year and nothing ever removed them.
  test "maintenance prunes long-read notifications and keeps the rest" do
    old_read    = notify!(1, read: true, at: 200.days.ago)
    old_unread  = notify!(2, read: false, at: 200.days.ago)
    fresh_read  = notify!(3, read: true, at: 3.days.ago)

    assert_equal 1, Maintenance.prune_notifications

    assert_not Notification.unscoped.exists?(old_read.id), "a read notice from 200 days ago goes"
    assert Notification.unscoped.exists?(old_unread.id), "never-read notices are kept"
    assert Notification.unscoped.exists?(fresh_read.id), "recent notices are kept"
  end
end
