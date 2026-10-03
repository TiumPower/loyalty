module Admin
  # Platform switches the super admin can flip at runtime — no deploy, no .env
  # edit: whether OTP codes are shown on screen (for testing), and the Zalo
  # OTP gateway's credentials.
  class SettingsController < BaseController
    def show
      @show_otp = AppSetting.show_otp?
      @gateway  = OtpGateway.status
    end

    def update
      AppSetting.set_flag(AppSetting::SHOW_OTP_KEY, params[:show_otp])
      redirect_to admin_settings_path,
                  notice: AppSetting.show_otp? ?
                    "Đã BẬT hiện mã OTP trên màn hình — chỉ dùng để test, nhớ tắt lại." :
                    "Đã tắt hiện mã OTP. Khách nhận mã qua Zalo (hoặc email) như bình thường."
    end

    # ---- Zalo OTP gateway ---------------------------------------------------
    # The refresh token rotates on every use, so the value in .env goes stale
    # after the first refresh; pasting a fresh one has to be possible without a
    # deploy.
    def update_gateway
      if OtpGateway.store_refresh_token(params[:zns_refresh_token])
        redirect_to admin_settings_path, notice: "Đã lưu refresh token Zalo OA mới."
      else
        redirect_to admin_settings_path, alert: "Chưa nhập refresh token."
      end
    end

    # Sends one real message to a real phone. Everything else about this gateway
    # can look correct while delivery silently fails — an unapproved template, a
    # wrong OA id, an expired token — so there has to be a way to actually try it.
    def test_otp
      result = OtpGateway.test_send(params[:phone])
      if result.ok?
        redirect_to admin_settings_path,
                    notice: "Đã gửi thử qua #{result.provider}. Kiểm tra Zalo trên số đó."
      else
        redirect_to admin_settings_path,
                    alert: "Gửi thử thất bại (#{result.provider || "chưa cấu hình"}): #{result.error}"
      end
    end

    private

    def nav_key = :settings
  end
end
