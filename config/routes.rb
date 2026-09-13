Rails.application.routes.draw do
  # ---- Devise auth (scoped paths) ----------------------------------------
  # Merchant staff/owner → /merchant/login ; Super admin → /admin/login.
  devise_for :users,
             path: "merchant",
             path_names: { sign_in: "login", sign_out: "logout", password: "password" },
             controllers: { sessions: "users/sessions" },
             skip: [:registrations]
  devise_for :admin_users,
             path: "admin",
             path_names: { sign_in: "login", sign_out: "logout", password: "password" },
             skip: [:registrations]
  # Member (customer) uses a custom phone+OTP flow; register the Devise mapping
  # for the Warden session helpers but not its routes.
  devise_for :members, skip: :all

  # ---- PayOS webhook (no CSRF) -------------------------------------------
  post "webhooks/payos" => "webhooks/payos#receive", as: :payos_webhook

  # ---- PWA (per-workspace, dynamic) --------------------------------------
  # Per-shop app icon drawn from the shop's initials (fallback when no logo).
  # The optional /w/:workspace_slug prefix mirrors the customer app so it
  # resolves in dev, where shops live on a path rather than a subdomain.
  scope "(/w/:workspace_slug)" do
    get "shop-icon(-:size).:format" => "pwa/icons#show", as: :pwa_icon,
        constraints: { format: /svg|png/, size: /\d+/ }
  end
  # Same optional slug prefix as the icon, so the manifest resolves its shop in
  # dev too. On production the shop subdomain resolves it and no slug is used.
  scope "(/w/:workspace_slug)" do
    get "manifest.webmanifest" => "pwa/manifests#show",     as: :pwa_manifest
  end
  get "service-worker.js"    => "pwa/service_workers#show", as: :pwa_service_worker

  # ---- Locale toggle (shared) --------------------------------------------
  get "/set_locale/:locale", to: "locales#update", as: :set_locale

  # ---- Super Admin (platform ops) : /admin -------------------------------
  namespace :admin do
    root "dashboard#show"
    resources :workspaces, only: [:index, :new, :create, :show, :update, :destroy] do
      member do
        patch :approve
        patch :suspend
        patch :reactivate
      end
    end
    get "monitoring", to: "monitoring#show"
    get "billing",    to: "billing#show"
    resources :plans, only: [:index, :update]
    get   "account", to: "account#edit",   as: :account
    patch "account", to: "account#update"
  end

  # ---- Merchant self-serve signup (public) -------------------------------
  get  "/merchant/signup", to: "merchant/signups#new",    as: :merchant_signup
  post "/merchant/signup", to: "merchant/signups#create"

  # ---- Merchant dashboard : /merchant ------------------------------------
  namespace :merchant do
    root "dashboard#show"
    get  "choose",            to: "choose#show",              as: :choose
    patch "tiers",            to: "tiers#update",             as: :tiers
    resource :account, only: [:show, :update], controller: "account"
    get "quick_login_qr", to: "account#quick_login_qr", as: :quick_login_qr
    get "go/:token",      to: "quick_logins#create",    as: :quick_login
    get  "checkin_qr",        to: "dashboard#checkin_qr",     as: :checkin_qr
    post "checkin_qr/rotate", to: "dashboard#rotate_checkin", as: :rotate_checkin
    get  "insights/busy_hour",         to: "dashboard#busy_hour",         as: :busy_hour_insight
    post "insights/busy_hour/refresh", to: "dashboard#refresh_busy_hour", as: :refresh_busy_hour_insight
    # First-run onboarding wizard
    get   "onboarding",      to: "onboarding#show",   as: :onboarding
    patch "onboarding",      to: "onboarding#update"
    post  "onboarding/skip", to: "onboarding#skip",   as: :skip_onboarding
    post "switch_workspace/:id", to: "workspaces#switch", as: :switch_workspace
    resource :loyalty_program, only: [:show, :update], path: "program"
    resource :appearance,      only: [:show, :update], path: "appearance" do
      post :suggest_theme # AI palette suggestion from the uploaded logo (JSON)
    end
    # No :new — the outlets index carries the "add branch" form inline, and
    # there has never been a new.html.erb, so the route only served an error.
    resources :outlets, except: [:new] do
      member { get :checkin_qr }
    end
    resources :staff, only: [:index, :create, :update, :destroy]
    resource  :domain, only: [:show, :update], controller: "domains" do
      post :verify
    end
    resource  :billing, only: [:show], controller: "billing"
    post  "billing/pay",        to: "payments#create", as: :billing_pay
    post  "billing/repay/:id",  to: "payments#repay",  as: :billing_repay
    get   "billing/return",     to: "payments#return", as: :billing_return
    patch "billing/auto_renew", to: "payments#auto_renew", as: :billing_auto_renew
    resources :customers, only: [:index, :show, :destroy] do
      member { post :adjust }
    end
    resources :transactions, only: [:index]
    # Undo a mis-rung bill (reverses points + revenue; see VoidPurchase).
    post "purchases/:id/void", to: "purchases#void", as: :void_purchase
    # In-app alert inbox for the shop (new reviews, out-of-stock rewards…).
    resources :alerts, only: [:index]
    get   "feedback", to: "feedback#show",   as: :feedback
    patch "feedback", to: "feedback#update"
    # Trả lời một đánh giá của khách (hiển thị công khai + báo cho khách).
    patch "feedback/:id/reply", to: "feedback#reply", as: :reply_feedback
    resource :automations, only: [:show, :update], controller: "automations"
    resources :broadcasts, only: [:index, :new, :create]
    resources :campaigns, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
      collection do
        post :generate_content # AI content suggestion (title/body), no persisted campaign
        get  :banner_jobs      # JSON poll for the global banner-generation progress bar
      end
      member do
        get   :qr      # downloadable promo QR (PNG)
        patch :pause   # running → paused (disables its promo QR)
        patch :resume  # paused → running
        patch :generate_banner # AI banner image (OpenAI) — async
        post  :push    # push the campaign to its audience
      end
    end
    # POS transaction QR (member self-scan / §6.2)
    post "pos", to: "pos#create", as: :pos_charges
    get  "scan-home", to: "scanner#launcher", as: :scan_home # minimal staff-mobile landing
    get  "scan-home/checkin-qr", to: "scanner#checkin_qr", as: :scanner_checkin_qr # branch check-in QR (standalone)
    get  "scanner", to: "scanner#show"
    # Counter scanner — Tích điểm (earn)
    post "earn/lookup", to: "earn#lookup", as: :earn_lookup
    post "earn",        to: "earn#create", as: :earn
    # Counter scanner — Xác thực ưu đãi (redeem/verify)
    post "redeem/lookup", to: "redeem#lookup", as: :redeem_lookup
    post "redeem",        to: "redeem#create", as: :redeem
    resources :rewards, only: [:index, :new, :create, :edit, :update, :destroy] do
      member { patch :toggle } # bật/tắt phát hành nhanh
    end
    # Gamification management
    get   "gamification",      to: "gamification#show"
    patch "gamification/wheel", to: "gamification#update_wheel", as: :wheel_config
    resources :stamp_cards, only: [:create, :update, :destroy]
    resources :missions,    only: [:create, :update, :destroy]
    resources :mission_submissions, only: [:index] do
      member do
        patch :approve
        patch :reject
      end
    end
    resources :badges,      only: [:create, :update, :destroy]
  end

  # ---- Customer PWA : shop subdomain / custom domain, or /w/:slug ---------
  # One route set; the :workspace_slug segment is optional. On a shop host the
  # Member::BaseController#default_url_options omits it (pretty URLs like
  # /wallet); in dev path-mode it is present (/w/cozycafe/wallet).
  scope "(/w/:workspace_slug)", module: :customer, as: :member do
    root "home#show", as: :root
    # phone + OTP auth
    get    "login",  to: "sessions#new",        as: :login
    post   "login",  to: "sessions#create"
    get    "verify", to: "sessions#verify_form", as: :verify
    post   "verify", to: "sessions#verify",      as: :verify_submit
    delete "logout", to: "sessions#destroy",     as: :logout
    # core tabs (fleshed out in later phases)
    get  "wallet",  to: "wallet#index",  as: :wallet
    get  "rewards/:id",        to: "rewards#show",  as: :reward
    post "rewards/:id/redeem", to: "rewards#redeem", as: :redeem_reward
    get  "vouchers/:id",        to: "vouchers#show",   as: :voucher
    post "vouchers/:id/use",    to: "vouchers#use",    as: :use_voucher
    get  "vouchers/:id/status", to: "vouchers#status", as: :voucher_status
    get "scan",         to: "scan#show",    as: :scan
    get "scan/resolve", to: "scan#resolve", as: :scan_resolve
    get "my-code", to: "codes#show",    as: :my_code
    get "my-code/token",  to: "codes#token",  as: :my_code_token   # fresh rotating QR
    get "my-code/recent", to: "codes#recent", as: :my_code_recent  # poll for a new earn
    get "history", to: "transactions#index", as: :history
    get "tier",    to: "tiers#show",    as: :tier
    # Web Push subscription (PWA)
    post "push/subscribe",   to: "push#subscribe",   as: :push_subscribe
    post "push/unsubscribe", to: "push#unsubscribe", as: :push_unsubscribe
    # Gamification
    get  "stamps",  to: "stamps#index",  as: :stamps
    get  "missions", to: "missions#index", as: :missions
    get  "missions/:id/submit", to: "missions#new_submission",    as: :new_mission_submission
    post "missions/:id/submit", to: "missions#create_submission", as: :mission_submission
    get  "badges",  to: "badges#index",  as: :badges
    get  "wheel",   to: "wheel#show",    as: :wheel
    post "wheel/spin", to: "wheel#spin",  as: :wheel_spin
    # CRM / notifications / referral
    get  "notifications", to: "notifications#index", as: :notifications
    post "notifications/read_all", to: "notifications#read_all", as: :read_all_notifications
    get  "refer",        to: "referrals#show", as: :refer
    get  "join/:code",   to: "sessions#join",  as: :join
    get   "me", to: "profile#show",   as: :profile
    patch "me", to: "profile#update"
    patch "me/avatar", to: "profile#avatar", as: :profile_avatar
    # Public shop / feedback page + reviews (members can leave many, edit own)
    get   "shop",            to: "reviews#index",  as: :shop_about
    get   "review",          to: "reviews#new",    as: :new_review
    post  "review",          to: "reviews#create", as: :reviews
    get   "review/:id/edit", to: "reviews#edit",   as: :edit_review
    patch "review/:id",      to: "reviews#update",  as: :review
  end

  # ---- Public shareable campaign link (OG preview for social sharing) -----
  get "/c/:share_slug", to: "public_campaigns#show", as: :public_campaign

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Bare-host root → Member::HomeController renders a dev launcher when no
  # workspace resolves (localhost with no subdomain/slug).
  root "customer/home#show"
end
