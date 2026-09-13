require "test_helper"

# What each role can actually reach. Staff and cashiers run the counter; they
# should not be able to change the programme, the plan, or who works here.
class StaffPermissionsTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "perms")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      @membership = Membership.create!(user: @user, workspace: @ws, role: "cashier")
      create(:loyalty_program, workspace: @ws)
      @member = create(:member, workspace: @ws)
    end
    sign_in @user
  end

  def as(role)
    ActsAsTenant.with_tenant(@ws) { @membership.update!(role: role) }
  end

  # The lambdas below are defined at class level, so run them against the
  # test instance.
  def blocked?(request)
    instance_exec(&request)
    # Guarded actions redirect to the dashboard with an alert.
    response.redirect? && flash[:alert].present?
  end

  MANAGER_ONLY = {
    "the loyalty programme" => -> { patch "/merchant/program", params: { loyalty_program: { earn_points: 99 } } },
    "staff roles"           => -> { post "/merchant/staff", params: { email: "x@y.vn", role: "manager" } },
    "the spin wheel"        => -> { patch "/merchant/gamification/wheel", params: { segments: {} } },
    "automations"           => -> { patch "/merchant/automations", params: { automations: {} } },
    "branding"              => -> { patch "/merchant/appearance", params: { workspace: { name: "X" } } },
  }.freeze

  MANAGER_ONLY.each do |what, request|
    test "a cashier cannot change #{what}" do
      as("cashier")
      assert blocked?(request), "a cashier reached #{what}"
    end

    test "a staff member cannot change #{what}" do
      as("staff")
      assert blocked?(request), "a staff member reached #{what}"
    end

    test "a manager can change #{what}" do
      as("manager")
      instance_exec(&request)
      assert_not(response.redirect? && flash[:alert].to_s.include?("quyền"),
                 "a manager was refused #{what}")
    end
  end

  test "a cashier cannot adjust a customer's points" do
    as("cashier")
    post "/merchant/customers/#{@member.id}/adjust", params: { amount: "100", note: "x" }
    assert_equal 0, @member.reload.points_balance
  end

  test "only an owner can delete a customer" do
    as("manager")
    assert_no_difference -> { ActsAsTenant.with_tenant(@ws) { Member.count } } do
      delete "/merchant/customers/#{@member.id}"
    end

    as("owner")
    assert_difference -> { ActsAsTenant.with_tenant(@ws) { Member.count } }, -1 do
      delete "/merchant/customers/#{@member.id}"
    end
  end

  test "every role can open the counter scanner" do
    %w[owner manager staff cashier].each do |role|
      as(role)
      get "/merchant/scanner"
      assert_response :success, "#{role} could not open the scanner"
    end
  end

  # A branch-locked staff member must not see the whole shop's customers.
  test "branch staff only see customers who transacted at their branch" do
    ActsAsTenant.with_tenant(@ws) do
      outlet = Outlet.create!(workspace: @ws, name: "CN1", code: "CN1")
      other  = Outlet.create!(workspace: @ws, name: "CN2", code: "CN2")
      @membership.update!(role: "staff", outlet: outlet)

      mine   = create(:member, workspace: @ws, name: "Khách Chi Nhánh Một")
      theirs = create(:member, workspace: @ws, name: "Khách Chi Nhánh Hai")
      Purchase.create!(workspace: @ws, member: mine, outlet: outlet, amount: 1000, points_earned: 1)
      Purchase.create!(workspace: @ws, member: theirs, outlet: other, amount: 1000, points_earned: 1)
    end

    get "/merchant/customers"
    assert_response :success
    assert_match "Khách Chi Nhánh Một", response.body
    assert_no_match(/Khách Chi Nhánh Hai/, response.body,
                    "branch staff saw another branch's customer")
  end
end

# Scheduling existed with no way to call a send back.
class BroadcastCancelTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "bcancel")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      @membership = Membership.create!(user: @user, workspace: @ws, role: "manager")
      3.times { create(:member, workspace: @ws) }
      @scheduled = @ws.broadcasts.create!(segment_key: "all", audience_label: "Tất cả",
                                          title: "Sale", body: "50%", scheduled_at: 2.hours.from_now)
    end
    sign_in @user
  end

  test "a scheduled broadcast can be cancelled before it goes out" do
    assert_difference -> { ActsAsTenant.with_tenant(@ws) { Broadcast.count } }, -1 do
      delete "/merchant/broadcasts/#{@scheduled.id}"
    end
    assert_match(/đã huỷ/i, flash[:notice].to_s)
  end

  test "a cancelled broadcast never reaches anyone" do
    delete "/merchant/broadcasts/#{@scheduled.id}"
    @scheduled.update_columns(scheduled_at: 1.minute.ago) rescue nil

    assert_no_difference -> { ActsAsTenant.with_tenant(@ws) { Notification.count } } do
      BroadcastDeliveryJob.new.perform
    end
  end

  test "a broadcast that already went out cannot be cancelled" do
    sent = ActsAsTenant.with_tenant(@ws) do
      @ws.broadcasts.create!(segment_key: "all", audience_label: "Tất cả", title: "T", body: "B",
                             sent_at: 1.hour.ago, sent_count: 3)
    end

    assert_no_difference -> { ActsAsTenant.with_tenant(@ws) { Broadcast.count } } do
      delete "/merchant/broadcasts/#{sent.id}"
    end
    assert_match(/không huỷ được/i, flash[:alert].to_s)
  end

  test "another shop's broadcast cannot be cancelled" do
    other = create(:workspace, subdomain: "bother")
    foreign = ActsAsTenant.with_tenant(other) do
      other.broadcasts.create!(segment_key: "all", title: "T", body: "B", scheduled_at: 1.hour.from_now)
    end

    delete "/merchant/broadcasts/#{foreign.id}"
    assert_response :not_found
  end

  test "a cashier cannot cancel a scheduled broadcast" do
    ActsAsTenant.with_tenant(@ws) { @membership.update!(role: "cashier") }
    assert_no_difference -> { ActsAsTenant.with_tenant(@ws) { Broadcast.count } } do
      delete "/merchant/broadcasts/#{@scheduled.id}"
    end
  end
end
