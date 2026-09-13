module Users
  # Merchant password reset. Devise only checks the token when the form is
  # SUBMITTED, so someone opening a stale link from their inbox filled in two
  # password boxes before being told it was dead. Check on arrival instead.
  class PasswordsController < Devise::PasswordsController
    def edit
      super
      flag_unusable_token
    end

    private

    def flag_unusable_token
      raw = params[:reset_password_token].to_s
      if raw.blank?
        resource.errors.add(:reset_password_token, :blank)
        return
      end
      digest = Devise.token_generator.digest(resource_class, :reset_password_token, raw)
      user = resource_class.find_by(reset_password_token: digest)
      if user.nil?
        resource.errors.add(:reset_password_token, :invalid)
      elsif !user.reset_password_period_valid?
        resource.errors.add(:reset_password_token, :expired)
      end
    end
  end
end
