require "test_helper"

# The conversion point of the whole funnel.
class MerchantSignupTest < ActionDispatch::IntegrationTest
  def sign_up(subdomain:, email: "moi@shop.vn", password: "password123", name: "Tiệm Mới")
    post "/merchant/signup", params: {
      workspace: { name: name, subdomain: subdomain, industry: "fnb" },
      email: email, owner_name: "Chủ Mới", password: password
    }
  end

  test "the form renders" do
    get "/merchant/signup"
    assert_response :success
    assert_select "input[name='workspace[subdomain]']"
  end

  test "a shop owner typing their shop's name gets a usable address" do
    assert_difference -> { Workspace.unscoped.count }, 1 do
      sign_up(subdomain: "Mộc Cà Phê")
    end
    assert_equal "moccaphe", Workspace.unscoped.order(:id).last.subdomain
  end

  test "spaces and punctuation are converted rather than rejected" do
    sign_up(subdomain: "My Shop!", email: "a@b.vn")
    assert_equal "myshop", Workspace.unscoped.order(:id).last.subdomain
  end

  test "a blank address falls back to the shop name" do
    sign_up(subdomain: "", name: "Quán Nhỏ", email: "c@d.vn")
    assert_equal "quan-nho", Workspace.unscoped.order(:id).last.subdomain
  end

  test "a taken address is refused with a free one suggested" do
    create(:workspace, subdomain: "moccaphe")

    assert_no_difference -> { Workspace.unscoped.count } do
      sign_up(subdomain: "moccaphe")
    end
    assert_response :unprocessable_entity
    assert_match "moccaphe2", response.body, "no alternative address was offered"
  end

  test "a reserved address is refused" do
    assert_no_difference -> { Workspace.unscoped.count } do
      sign_up(subdomain: "admin")
    end
    assert_response :unprocessable_entity
  end

  test "signing up starts a real trial, not an unpaid account" do
    sign_up(subdomain: "trialshop")
    ws = Workspace.unscoped.order(:id).last
    assert_equal "trial", ws.status
    assert ws.paid_until > Time.current
    assert_in_delta Workspace::TRIAL_DAYS, ((ws.paid_until - Time.current) / 1.day), 1
  end

  test "an existing email cannot be hijacked without its password" do
    existing = create(:user, email: "chu@shop.vn", password: "correct-horse")

    assert_no_difference -> { Workspace.unscoped.count } do
      sign_up(subdomain: "hijack", email: "chu@shop.vn", password: "guessing")
    end
    assert_response :unprocessable_entity
    assert_equal existing.encrypted_password, existing.reload.encrypted_password
  end

  test "an existing owner proving their password may open a second shop" do
    create(:user, email: "chu@shop.vn", password: "correct-horse")

    assert_difference -> { Workspace.unscoped.count }, 1 do
      sign_up(subdomain: "shoptwo", email: "chu@shop.vn", password: "correct-horse")
    end
  end

  test "a short password is refused" do
    assert_no_difference -> { Workspace.unscoped.count } do
      sign_up(subdomain: "shortpw", password: "12345")
    end
    assert_response :unprocessable_entity
  end

  test "the page states the trial length rather than just promising free" do
    get "/merchant/signup"
    assert_match(/#{Workspace::TRIAL_DAYS} ngày/, response.body)
    assert_no_match(/Miễn phí để bắt đầu/i, response.body)
  end
end
