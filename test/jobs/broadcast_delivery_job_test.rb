require "test_helper"

# Scheduled broadcasts land in a customer's inbox and on their phone.
class BroadcastDeliveryJobTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "bcast")
    ActsAsTenant.current_tenant = @ws
    @members = 3.times.map { create(:member, workspace: @ws) }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def scheduled(at: 1.minute.ago)
    @ws.broadcasts.create!(segment_key: "all", audience_label: "Tất cả",
                           title: "Khuyến mãi", body: "Ghé quán nhé", scheduled_at: at)
  end

  test "a due broadcast is delivered once" do
    b = scheduled
    assert_difference -> { Notification.count }, 3 do
      BroadcastDeliveryJob.new.perform
    end
    assert b.reload.sent_at.present?
    assert_equal 3, b.sent_count
  end

  test "a broadcast whose time has not come is left alone" do
    scheduled(at: 1.hour.from_now)
    assert_no_difference -> { Notification.count } do
      BroadcastDeliveryJob.new.perform
    end
  end

  # The job runs every five minutes; an overlapping run used to pick the same
  # broadcast up again because sent_at is only set after the notifications are
  # written, and every customer got the message twice.
  test "a second run does not deliver the same broadcast again" do
    scheduled
    BroadcastDeliveryJob.new.perform
    assert_no_difference -> { Notification.count } do
      BroadcastDeliveryJob.new.perform
    end
  end

  test "only one of two concurrent runs may claim a broadcast" do
    b = scheduled
    assert b.claim_for_delivery!, "the first caller should win"
    assert_not b.claim_for_delivery!, "a second caller claimed an already-claimed broadcast"
  end

  test "an already-sent broadcast is never re-claimed" do
    b = scheduled
    b.update!(sent_at: Time.current)
    assert_not b.claim_for_delivery!
  end
end
