require "test_helper"

# The platform console holds the most destructive action in the product and
# hands out shop-owner credentials.
class AdminWorkspaceAdminTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:admin_user)
    sign_in @admin, scope: :admin_user
    @ws = create(:workspace, name: "Quán Thử", subdomain: "quanthu")
  end

  # --- Purging a workspace -------------------------------------------------

  test "a purge without the typed subdomain does nothing" do
    assert_no_difference -> { Workspace.unscoped.count } do
      delete "/admin/workspaces/#{@ws.to_param}"
    end
    assert_match(/cần gõ đúng subdomain/i, flash[:alert].to_s)
  end

  test "a purge with the wrong subdomain does nothing" do
    assert_no_difference -> { Workspace.unscoped.count } do
      delete "/admin/workspaces/#{@ws.to_param}", params: { confirm: "quanth" }
    end
  end

  test "a purge with the exact subdomain goes through" do
    assert_difference -> { Workspace.unscoped.count }, -1 do
      delete "/admin/workspaces/#{@ws.to_param}", params: { confirm: "quanthu" }
    end
  end

  test "the workspace list no longer offers a one-click delete" do
    get "/admin/workspaces"
    assert_response :success
    # Scoped to workspace forms — the sidebar's logout is a delete too.
    ws_delete = %r{action="/admin/workspaces/[^"]+"[^>]*>\s*<input[^>]*value="delete"}
    assert_no_match(ws_delete, response.body, "the list still has a one-click delete")
  end

  test "the workspace page asks for the subdomain before deleting" do
    get "/admin/workspaces/#{@ws.to_param}"
    assert_response :success
    assert_select "input[name=confirm]", 1
    assert_match(/Vùng nguy hiểm/, response.body)
  end

  # --- Creating a workspace ------------------------------------------------

  def create_workspace(email:)
    post "/admin/workspaces", params: {
      workspace: { name: "Tiệm Mới", subdomain: "tiemmoi", industry: "fnb", plan: "starter" },
      owner_email: email, owner_name: "Chủ Mới"
    }
  end

  test "the owner password never reaches the flash notice" do
    create_workspace(email: "chu@tiemmoi.vn")
    owner = User.find_by(email: "chu@tiemmoi.vn")
    assert owner.present?
    # stash_toast_cookie copies :notice and :alert verbatim into a JS-readable
    # cookie, so a credential must never travel in either.
    assert_no_match(/\b[A-Za-z0-9]{10}\b/, flash[:notice].to_s.sub("Tiệm Mới", ""),
                    "a generated password looks like it is still in the notice")
    assert_not_includes flash[:notice].to_s, "/"
  end

  test "an existing owner is not shown a password that would not work" do
    existing = create(:user, email: "sanco@shop.vn")
    original_digest = existing.encrypted_password

    create_workspace(email: "sanco@shop.vn")

    assert_equal original_digest, existing.reload.encrypted_password, "the existing password changed"
    assert_match(/đã có tài khoản/i, flash[:notice].to_s)
    assert_nil flash[:owner_credentials]
  end
end
