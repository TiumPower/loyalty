require "test_helper"

# A full card whose prize ran out used to reset itself and count the completion,
# so the customer lost the whole card and got nothing — silently. It is now held
# with its stamps until the merchant restocks.
class StampCardHoldTest < ActiveSupport::TestCase
  setup do
    @ws = create(:workspace, subdomain: "stamphold", status: "trial")
    ActsAsTenant.with_tenant(@ws) do
      @reward = Reward.create!(workspace: @ws, title: "Cà phê", kind: "gift", value_unit: "item",
                               active: true, stock: 1)
      @card = StampCard.create!(workspace: @ws, title: "Mua 2 tặng 1", target_count: 2,
                                reward: @reward, active: true)
      @member = create(:member, workspace: @ws)
      @other  = create(:member, workspace: @ws)
    end
  end

  def fill(member)
    sm = ActsAsTenant.with_tenant(@ws) { @card.membership_for(member) }
    2.times.map { sm.add_stamp! }.last
  end

  test "the first customer gets the prize" do
    result = fill(@member)
    assert result[:completed]
    assert result[:voucher].present?
    assert_not result[:held]
  end

  test "once it runs out the card is held full instead of being spent" do
    fill(@member) # takes the only unit
    result = fill(@other)

    assert_not result[:completed]
    assert result[:held]
    assert result[:newly_held]
    sm = ActsAsTenant.with_tenant(@ws) { @card.membership_for(@other) }
    assert_equal 2, sm.count, "the stamps were taken from the customer"
    assert_equal 0, sm.completed_count
    assert sm.held_for_stock?
  end

  test "a held card does not run past its goal and only warns once" do
    fill(@member)
    fill(@other)
    sm = ActsAsTenant.with_tenant(@ws) { @card.membership_for(@other) }

    result = sm.add_stamp!
    assert result[:held]
    assert_not result[:newly_held], "the customer would be told again on every stamp"
    assert_equal 2, sm.reload.count
  end

  test "restocking pays out every held card, oldest first, until stock runs out" do
    fill(@member)
    fill(@other)
    third = ActsAsTenant.with_tenant(@ws) { create(:member, workspace: @ws) }
    fill(third)

    ActsAsTenant.with_tenant(@ws) { @reward.update!(stock: 2) } # room for one more only
    assert_equal 1, Gamification.settle_held_cards(@reward.reload)

    settled, still_held = ActsAsTenant.with_tenant(@ws) do
      [@card.membership_for(@other), @card.membership_for(third)]
    end
    assert_equal 0, settled.count
    assert_equal 1, settled.completed_count
    assert_equal 2, still_held.count, "the second held card must keep waiting"
  end

  test "a card without any reward still completes and resets" do
    plain = ActsAsTenant.with_tenant(@ws) do
      StampCard.create!(workspace: @ws, title: "Không quà", target_count: 2, active: true)
    end
    sm = ActsAsTenant.with_tenant(@ws) { plain.membership_for(@member) }
    2.times { sm.add_stamp! }
    assert_equal 0, sm.reload.count
    assert_equal 1, sm.completed_count
  end
end
