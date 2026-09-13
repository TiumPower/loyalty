require "test_helper"

# The profile screen holds the only identifier a customer has. There is no
# password and no recovery, so the email field is not an ordinary text field.
class CustomerProfileTest < ActionDispatch::IntegrationTest
  setup do
    @ws = create(:workspace, subdomain: "profws")
    @ws.update!(settings: @ws.settings.merge("onboarded" => true))
    ActsAsTenant.with_tenant(@ws) do
      create(:loyalty_program, workspace: @ws)
      @member = create(:member, workspace: @ws, email: "me@example.com", name: "Ngọc")
      @member.point_transactions.create!(workspace: @ws, kind: "earn", amount: 900)
      @member.recompute_points!
    end
    sign_in_member!
  end

  def base = "/w/#{@ws.slug}"

  def sign_in_member!
    post "#{base}/login", params: { email: @member.email }
    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: @member.email, purpose: "login").order(:id).last
    post "#{base}/verify", params: { code: ch.code }
  end

  def upload(name, type, bytes)
    path = Rails.root.join("tmp", name)
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path, type)
  end

  # Email is the login: there is no password, and signing in with an unknown
  # address silently creates a NEW member. A typo here therefore stranded the
  # customer's points on an orphaned record and handed them an empty account,
  # with nothing to tell them what happened and no way back.
  test "changing the email does not take effect until the new address is proven" do
    patch "#{base}/me", params: { member: { name: "Ngọc", email: "typo@example.com" } }
    assert_redirected_to "#{base}/me/confirm-email"
    assert_equal "me@example.com", @member.reload.email, "the login identifier is untouched"

    ch = OtpChallenge.unscoped.where(workspace_id: @ws.id, email: "typo@example.com",
                                     purpose: "email_change").order(:id).last
    assert ch, "a code was sent to the NEW address"

    post "#{base}/me/confirm-email", params: { code: "000000" }
    assert_response :unprocessable_entity
    assert_equal "me@example.com", @member.reload.email

    post "#{base}/me/confirm-email", params: { code: ch.code }
    assert_redirected_to "#{base}/me"
    assert_equal "typo@example.com", @member.reload.email
  end

  # Everything else on the form saves the moment it is submitted.
  test "the rest of the profile still saves in one step" do
    patch "#{base}/me", params: { member: { name: "Ngọc Mới", phone: "0912345678", birthday: "01/03/1994" } }
    assert_redirected_to "#{base}/me"
    @member.reload
    assert_equal "Ngọc Mới", @member.name
    assert_equal "0912345678", @member.phone
    assert_equal Date.new(1994, 3, 1), @member.birthday
  end

  test "an email already used in this shop is refused before any code is sent" do
    ActsAsTenant.with_tenant(@ws) { create(:member, workspace: @ws, email: "taken@example.com") }
    patch "#{base}/me", params: { member: { email: "taken@example.com" } }
    assert_response :unprocessable_entity
    assert_nil OtpChallenge.unscoped.where(workspace_id: @ws.id, email: "taken@example.com",
                                           purpose: "email_change").last
    assert_equal "me@example.com", @member.reload.email
  end

  # The avatar had no checks at all, while the merchant's logo — the same kind of
  # upload — has had a type and size limit for a while. It is shown to other
  # customers on the reviews page.
  test "the avatar must be a reasonably sized image" do
    patch "#{base}/me/avatar", params: { member: { avatar: upload("evil.pdf", "application/pdf", "%PDF-1.4 not an image") } }
    assert_redirected_to "#{base}/me"
    refute @member.reload.avatar.attached?, "a PDF is not an avatar"

    big = upload("huge.png", "image/png", "\x89PNG\r\n\x1a\n".b + ("x" * (Member::AVATAR_MAX_BYTES + 1)))
    patch "#{base}/me/avatar", params: { member: { avatar: big } }
    assert_redirected_to "#{base}/me"
    refute @member.reload.avatar.attached?, "oversized uploads are refused"

    ok = upload("ok.png", "image/png", "\x89PNG\r\n\x1a\n".b + "small")
    patch "#{base}/me/avatar", params: { member: { avatar: ok } }
    assert_redirected_to "#{base}/me"
    assert @member.reload.avatar.attached?, "a real image still goes through"
  end

  test "a birthday outside a plausible range is refused" do
    patch "#{base}/me", params: { member: { birthday: "01/01/#{Date.current.year + 2}" } }
    assert_response :unprocessable_entity
    assert_nil @member.reload.birthday

    patch "#{base}/me", params: { member: { birthday: "01/01/1850" } }
    assert_response :unprocessable_entity
    assert_nil @member.reload.birthday
  end
end
