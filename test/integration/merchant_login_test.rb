require "test_helper"

# Sign-in and password reset for shop owners.
class MerchantLoginTest < ActionDispatch::IntegrationTest
  setup { @user = create(:user, email: "real@shop.vn", password: "correct-horse") }

  test "the login page renders" do
    get "/merchant/login"
    assert_response :success
    assert_select "input[name='user[email]']"
    assert_select "input[name='user[password]']"
  end

  test "correct credentials sign the owner in" do
    post "/merchant/login", params: { user: { email: "real@shop.vn", password: "correct-horse" } }
    assert_response :redirect
    follow_redirect!
    assert_no_match(/Đăng nhập cửa hàng/, response.body)
  end

  test "a wrong password is refused" do
    post "/merchant/login", params: { user: { email: "real@shop.vn", password: "nope" } }
    assert_response :unprocessable_entity
  end

  # A login form that answers differently for a known and an unknown address
  # tells an attacker which shop owners are registered.
  test "login does not reveal whether an email exists" do
    post "/merchant/login", params: { user: { email: "real@shop.vn", password: "wrong" } }
    known = [response.status, flash[:alert].to_s]

    post "/merchant/login", params: { user: { email: "nobody@nowhere.vn", password: "wrong" } }
    assert_equal known, [response.status, flash[:alert].to_s]
  end

  # This one did leak: a known email redirected (303), an unknown one
  # re-rendered the form (422).
  test "password reset does not reveal whether an email exists" do
    post "/merchant/password", params: { user: { email: "real@shop.vn" } }
    known = [response.status, response.location, flash[:notice].to_s]

    post "/merchant/password", params: { user: { email: "nobody@nowhere.vn" } }
    assert_equal known, [response.status, response.location, flash[:notice].to_s],
                 "the response still differs for a registered address"
  end

  test "a reset for a real account actually sends mail" do
    assert_emails 1 do
      post "/merchant/password", params: { user: { email: "real@shop.vn" } }
    end
  end

  test "a reset for an unknown address sends nothing" do
    assert_emails 0 do
      post "/merchant/password", params: { user: { email: "nobody@nowhere.vn" } }
    end
  end

  test "the reset link sets a new password and signs the owner in" do
    token = @user.send(:set_reset_password_token)
    put "/merchant/password", params: {
      user: { reset_password_token: token, password: "brand-new-pass", password_confirmation: "brand-new-pass" }
    }
    assert_response :redirect
    assert @user.reload.valid_password?("brand-new-pass")
  end

  test "an expired reset token is refused" do
    token = @user.send(:set_reset_password_token)
    @user.update_columns(reset_password_sent_at: 7.hours.ago) # config.reset_password_within = 6.hours

    put "/merchant/password", params: {
      user: { reset_password_token: token, password: "brand-new-pass", password_confirmation: "brand-new-pass" }
    }
    assert_not @user.reload.valid_password?("brand-new-pass")
  end

  # --- The reset page itself ----------------------------------------------

  test "a dead link offers a new one instead of two useless password boxes" do
    token = @user.send(:set_reset_password_token)
    @user.update_columns(reset_password_sent_at: 7.hours.ago)

    put "/merchant/password", params: {
      user: { reset_password_token: token, password: "brand-new-pass", password_confirmation: "brand-new-pass" }
    }
    assert_response :unprocessable_entity
    assert_match(/Liên kết không dùng được/, response.body)
    assert_select "a[href=?]", "/merchant/password/new"
    assert_select "input[name='user[password]']", 0, "the unusable form is still on screen"
  end

  test "a mismatch says so in readable Vietnamese" do
    token = @user.send(:set_reset_password_token)
    put "/merchant/password", params: {
      user: { reset_password_token: token, password: "abcdefgh", password_confirmation: "different" }
    }
    assert_match(/Xác nhận mật khẩu không khớp/, response.body)
    # Used to render "không khớp với xác nhận" — the interpolation landing wrong.
    assert_no_match(/không khớp với xác nhận/, response.body)
  end

  test "a stale link says so on arrival, before anything is typed" do
    token = @user.send(:set_reset_password_token)
    @user.update_columns(reset_password_sent_at: 7.hours.ago)

    get "/merchant/password/edit", params: { reset_password_token: token }
    assert_response :success
    assert_match(/Liên kết không dùng được/, response.body)
    assert_select "input[name='user[password]']", 0,
                  "two password boxes that can never work are still on screen"
    assert_select "a[href=?]", "/merchant/password/new"
  end

  test "a made-up token is caught on arrival too" do
    get "/merchant/password/edit", params: { reset_password_token: "not-a-real-token" }
    assert_match(/Liên kết không dùng được/, response.body)
    assert_select "input[name='user[password]']", 0
  end

  test "a valid link still shows the form" do
    token = @user.send(:set_reset_password_token)
    get "/merchant/password/edit", params: { reset_password_token: token }
    assert_response :success
    assert_no_match(/Liên kết không dùng được/, response.body)
    assert_select "input[name='user[password]']", 1
  end

  test "the reset form can reveal what was typed" do
    token = @user.send(:set_reset_password_token)
    get "/merchant/password/edit", params: { reset_password_token: token }
    assert_response :success
    assert_select "[data-controller=reveal]"
    assert_select "input[name='user[password]']"
    assert_select "input[name='user[password_confirmation]']"
  end

  test "the reset email is multipart and states how long the link lasts" do
    post "/merchant/password", params: { user: { email: "real@shop.vn" } }
    mail = ActionMailer::Base.deliveries.last
    assert mail.multipart?, "HTML-only mail lands in spam and has no plain-text fallback"

    body = mail.parts.map { |p| p.body.to_s }.join("
")
    hours = (Devise.reset_password_within / 1.hour).to_i
    assert_match(/#{hours} gi/, body, "the email does not say when the link expires")
    assert_match %r{password/edit}, body
  end

  test "the login page points at signup and password reset" do
    get "/merchant/login"
    assert_select "a[href=?]", "/merchant/signup"
    assert_select "a[href=?]", "/merchant/password/new"
  end
end
