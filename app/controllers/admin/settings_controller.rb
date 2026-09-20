module Admin
  # Platform switches the super admin can flip at runtime — no deploy, no .env
  # edit. Today: whether OTP codes are shown on screen (for testing).
  class SettingsController < BaseController
    def show
      @show_otp = AppSetting.show_otp?
    end

    def update
      AppSetting.set_flag(AppSetting::SHOW_OTP_KEY, params[:show_otp])
      redirect_to admin_settings_path,
                  notice: AppSetting.show_otp? ?
                    "Đã BẬT hiện mã OTP trên màn hình — chỉ dùng để test, nhớ tắt lại." :
                    "Đã tắt hiện mã OTP. Khách nhận mã qua email như bình thường."
    end

    private

    def nav_key = :settings
  end
end
