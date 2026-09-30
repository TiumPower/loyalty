require "test_helper"

# The three lifecycle automations are now edited one at a time, from their own
# screen. Saving one must leave the other two exactly as they were — the old
# form posted all three together, so a per-kind save that forgot to merge would
# silently switch the others off.
class AutomationEditorTest < ActionDispatch::IntegrationTest
  setup do
    @ws   = create(:workspace, subdomain: "autos")
    @user = create(:user)
    ActsAsTenant.with_tenant(@ws) do
      Membership.create!(user: @user, workspace: @ws, role: "owner")
      @reward = Reward.create!(workspace: @ws, title: "Cà phê", kind: "voucher",
                               cost_points: 100, value_unit: "item", active: true)
    end
    @ws.update!(settings: @ws.settings.merge("automations" => {
      "welcome"  => { "enabled" => true,  "reward_id" => @reward.id.to_s },
      "birthday" => { "enabled" => true,  "reward_id" => @reward.id.to_s },
      "winback"  => { "enabled" => false, "reward_id" => nil, "days" => 45, "message" => "Ghé lại nhé" },
    }))
    sign_in @user
  end

  def autos = @ws.reload.settings.fetch("automations")

  test "saving one automation leaves the others untouched" do
    patch "/merchant/automations", params: {
      kind: "winback",
      automations: { "winback" => { "enabled" => "1", "days" => "60", "message" => "Nhớ bạn" } },
    }

    assert_equal true, autos.dig("winback", "enabled")
    assert_equal 60,   autos.dig("winback", "days")
    assert_equal "Nhớ bạn", autos.dig("winback", "message")
    # The two the merchant did not open stay on, with their gift.
    assert_equal true, autos.dig("welcome", "enabled")
    assert_equal true, autos.dig("birthday", "enabled")
    assert_equal @reward.id.to_s, autos.dig("birthday", "reward_id")
  end

  test "turning one off does not disturb the rest" do
    patch "/merchant/automations", params: {
      kind: "welcome", automations: { "welcome" => { "enabled" => "0" } },
    }

    assert_equal false, autos.dig("welcome", "enabled")
    assert_equal true,  autos.dig("birthday", "enabled")
    assert_equal 45,    autos.dig("winback", "days")
  end

  # The pre-existing whole-set form (no :kind) must keep working.
  test "a post without a kind still writes all three" do
    patch "/merchant/automations", params: {
      automations: {
        "welcome"  => { "enabled" => "0" },
        "birthday" => { "enabled" => "0" },
        "winback"  => { "enabled" => "1", "days" => "20" },
      },
    }

    assert_equal false, autos.dig("welcome", "enabled")
    assert_equal false, autos.dig("birthday", "enabled")
    assert_equal 20,    autos.dig("winback", "days")
  end

  test "an unknown kind edits the first automation rather than 404ing" do
    get "/merchant/automations/nonsense/edit"
    assert_response :success
  end
end
