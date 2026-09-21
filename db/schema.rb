# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_09_21_152743) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "name", default: "", null: false
    t.string "role", default: "operator", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "badges", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.string "icon"
    t.string "criteria_type", default: "purchases_count", null: false
    t.integer "threshold", default: 1, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "reward_points", default: 0, null: false
    t.bigint "reward_id"
    t.index ["reward_id"], name: "index_badges_on_reward_id"
    t.index ["workspace_id", "key"], name: "index_badges_on_workspace_id_and_key", unique: true
    t.index ["workspace_id"], name: "index_badges_on_workspace_id"
  end

  create_table "broadcasts", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "created_by_id"
    t.string "segment_key", default: "all", null: false
    t.string "title", null: false
    t.text "body"
    t.integer "sent_count", default: 0, null: false
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "scheduled_at"
    t.bigint "campaign_id"
    t.string "audience_label"
    t.bigint "audience_outlet_id"
    t.string "audience_query"
    t.string "audience_tier"
    t.index ["campaign_id"], name: "index_broadcasts_on_campaign_id"
    t.index ["created_by_id"], name: "index_broadcasts_on_created_by_id"
    t.index ["scheduled_at"], name: "index_broadcasts_on_scheduled_at"
    t.index ["workspace_id"], name: "index_broadcasts_on_workspace_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "reward_id"
    t.string "name", null: false
    t.string "campaign_type", default: "promo_voucher", null: false
    t.string "status", default: "draft", null: false
    t.string "audience", default: "all", null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.jsonb "content", default: {}, null: false
    t.jsonb "metrics", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "share_slug"
    t.string "banner_status"
    t.datetime "banner_requested_at"
    t.boolean "banner_has_qr", default: false, null: false
    t.index ["reward_id"], name: "index_campaigns_on_reward_id"
    t.index ["share_slug"], name: "index_campaigns_on_share_slug", unique: true
    t.index ["workspace_id", "status"], name: "index_campaigns_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_campaigns_on_workspace_id"
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "plan", null: false
    t.integer "amount", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.date "period_start", null: false
    t.date "period_end", null: false
    t.bigint "payos_order_code"
    t.string "checkout_url"
    t.datetime "paid_at"
    t.jsonb "gateway_response", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payos_order_code"], name: "index_invoices_on_payos_order_code", unique: true, where: "(payos_order_code IS NOT NULL)"
    t.index ["workspace_id", "status"], name: "index_invoices_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_invoices_on_workspace_id"
  end

  create_table "loyalty_programs", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.boolean "points_enabled", default: true, null: false
    t.boolean "tiers_enabled", default: true, null: false
    t.boolean "stamps_enabled", default: false, null: false
    t.boolean "gamification_enabled", default: false, null: false
    t.integer "earn_points", default: 1, null: false
    t.integer "earn_per_amount", default: 10000, null: false
    t.string "currency", default: "VND", null: false
    t.string "scan_mode", default: "staff_scans_member", null: false
    t.integer "tier_cycle_months", default: 12, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "referral_enabled", default: true, null: false
    t.integer "referral_points", default: 100, null: false
    t.integer "points_expiry_months", default: 0, null: false
    t.index ["workspace_id"], name: "index_loyalty_programs_on_workspace_id", unique: true
  end

  create_table "member_badges", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.bigint "badge_id", null: false
    t.datetime "earned_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["badge_id"], name: "index_member_badges_on_badge_id"
    t.index ["member_id", "badge_id"], name: "index_member_badges_on_member_id_and_badge_id", unique: true
    t.index ["member_id"], name: "index_member_badges_on_member_id"
    t.index ["workspace_id"], name: "index_member_badges_on_workspace_id"
  end

  create_table "members", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "phone"
    t.string "email"
    t.string "name", default: "", null: false
    t.date "birthday"
    t.string "locale", default: "vi", null: false
    t.string "gender"
    t.integer "points_balance", default: 0, null: false
    t.integer "lifetime_points", default: 0, null: false
    t.string "tier_key"
    t.bigint "referred_by_id"
    t.string "referral_code"
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_checkin_at"
    t.string "join_source"
    t.index ["referred_by_id"], name: "index_members_on_referred_by_id"
    t.index ["workspace_id", "join_source"], name: "index_members_on_workspace_id_and_join_source"
    t.index ["workspace_id", "phone"], name: "index_members_on_workspace_id_and_phone", unique: true
    t.index ["workspace_id", "referral_code"], name: "index_members_on_workspace_id_and_referral_code", unique: true, where: "(referral_code IS NOT NULL)"
    t.index ["workspace_id", "tier_key"], name: "index_members_on_workspace_id_and_tier_key"
    t.index ["workspace_id"], name: "index_members_on_workspace_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "workspace_id", null: false
    t.bigint "outlet_id"
    t.string "role", default: "staff", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["outlet_id"], name: "index_memberships_on_outlet_id"
    t.index ["user_id", "workspace_id"], name: "index_memberships_on_user_id_and_workspace_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.index ["workspace_id"], name: "index_memberships_on_workspace_id"
  end

  create_table "merchant_alerts", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body"
    t.string "icon"
    t.string "link"
    t.string "level", default: "info", null: false
    t.string "dedup_key"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "created_at"], name: "index_merchant_alerts_on_workspace_id_and_created_at"
    t.index ["workspace_id", "dedup_key"], name: "index_merchant_alerts_on_workspace_id_and_dedup_key", unique: true, where: "(dedup_key IS NOT NULL)"
    t.index ["workspace_id", "read_at"], name: "index_merchant_alerts_on_workspace_id_and_read_at"
    t.index ["workspace_id"], name: "index_merchant_alerts_on_workspace_id"
  end

  create_table "mission_progresses", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.bigint "mission_id", null: false
    t.string "period_key", null: false
    t.integer "progress", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "approval_status"
    t.datetime "submitted_at"
    t.string "platform"
    t.text "note"
    t.jsonb "ai_verdict", default: {}, null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.index ["approval_status"], name: "index_mission_progresses_on_approval_status"
    t.index ["member_id", "mission_id", "period_key"], name: "idx_mission_progress_unique", unique: true
    t.index ["member_id"], name: "index_mission_progresses_on_member_id"
    t.index ["mission_id"], name: "index_mission_progresses_on_mission_id"
    t.index ["workspace_id"], name: "index_mission_progresses_on_workspace_id"
  end

  create_table "missions", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "title", null: false
    t.string "icon"
    t.string "mission_type", default: "checkin", null: false
    t.string "period", default: "daily", null: false
    t.integer "goal", default: 1, null: false
    t.integer "reward_points", default: 20, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "proof_config", default: {}, null: false
    t.index ["workspace_id"], name: "index_missions_on_workspace_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.bigint "broadcast_id"
    t.string "title", null: false
    t.text "body"
    t.string "kind", default: "promo", null: false
    t.string "icon"
    t.string "deep_link"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["broadcast_id"], name: "index_notifications_on_broadcast_id"
    t.index ["member_id", "created_at"], name: "index_notifications_on_member_id_and_created_at"
    t.index ["member_id", "read_at"], name: "index_notifications_on_member_id_and_read_at"
    t.index ["member_id"], name: "index_notifications_on_member_id"
    t.index ["workspace_id"], name: "index_notifications_on_workspace_id"
  end

  create_table "otp_challenges", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "phone"
    t.string "code", null: false
    t.string "purpose", default: "login", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email"
    t.index ["workspace_id", "email"], name: "index_otp_challenges_on_workspace_id_and_email"
    t.index ["workspace_id", "phone", "purpose"], name: "index_otp_challenges_on_workspace_id_and_phone_and_purpose"
    t.index ["workspace_id"], name: "index_otp_challenges_on_workspace_id"
  end

  create_table "outlets", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "name", null: false
    t.string "code"
    t.string "address"
    t.string "phone"
    t.boolean "active", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "code"], name: "index_outlets_on_workspace_id_and_code", unique: true, where: "(code IS NOT NULL)"
    t.index ["workspace_id"], name: "index_outlets_on_workspace_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.integer "price", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.integer "max_outlets"
    t.integer "max_members"
    t.boolean "allow_stamps", default: true, null: false
    t.boolean "allow_gamification", default: true, null: false
    t.boolean "allow_campaigns", default: true, null: false
    t.boolean "allow_custom_domain", default: false, null: false
    t.boolean "allow_ab_testing", default: false, null: false
    t.jsonb "features", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_plans_on_key", unique: true
  end

  create_table "point_transactions", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.bigint "outlet_id"
    t.bigint "staff_id"
    t.string "source_type"
    t.bigint "source_id"
    t.string "kind", default: "earn", null: false
    t.integer "amount", default: 0, null: false
    t.string "note"
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id", "kind"], name: "index_point_transactions_on_member_id_and_kind"
    t.index ["member_id"], name: "index_point_transactions_on_member_id"
    t.index ["outlet_id"], name: "index_point_transactions_on_outlet_id"
    t.index ["source_type", "source_id"], name: "index_point_transactions_on_source"
    t.index ["staff_id"], name: "index_point_transactions_on_staff_id"
    t.index ["workspace_id", "member_id", "created_at"], name: "idx_on_workspace_id_member_id_created_at_4504b54a31"
    t.index ["workspace_id"], name: "index_point_transactions_on_workspace_id"
  end

  create_table "pos_charges", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "outlet_id"
    t.bigint "staff_id"
    t.bigint "member_id"
    t.bigint "purchase_id"
    t.string "token", null: false
    t.integer "amount", default: 0, null: false
    t.string "state", default: "open", null: false
    t.integer "points_awarded", default: 0, null: false
    t.datetime "expires_at"
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id"], name: "index_pos_charges_on_member_id"
    t.index ["outlet_id"], name: "index_pos_charges_on_outlet_id"
    t.index ["purchase_id"], name: "index_pos_charges_on_purchase_id"
    t.index ["staff_id"], name: "index_pos_charges_on_staff_id"
    t.index ["workspace_id", "token"], name: "index_pos_charges_on_workspace_id_and_token", unique: true
    t.index ["workspace_id"], name: "index_pos_charges_on_workspace_id"
  end

  create_table "promo_claims", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "promo_code_id", null: false
    t.bigint "member_id", null: false
    t.bigint "voucher_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id"], name: "index_promo_claims_on_member_id"
    t.index ["promo_code_id", "member_id"], name: "index_promo_claims_on_promo_code_id_and_member_id", unique: true
    t.index ["promo_code_id"], name: "index_promo_claims_on_promo_code_id"
    t.index ["voucher_id"], name: "index_promo_claims_on_voucher_id"
    t.index ["workspace_id"], name: "index_promo_claims_on_workspace_id"
  end

  create_table "promo_codes", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "campaign_id"
    t.bigint "reward_id", null: false
    t.string "token", null: false
    t.integer "max_claims"
    t.integer "claims_count", default: 0, null: false
    t.integer "scan_count", default: 0, null: false
    t.integer "per_member_limit", default: 1, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_promo_codes_on_campaign_id"
    t.index ["reward_id"], name: "index_promo_codes_on_reward_id"
    t.index ["workspace_id", "token"], name: "index_promo_codes_on_workspace_id_and_token", unique: true
    t.index ["workspace_id"], name: "index_promo_codes_on_workspace_id"
  end

  create_table "purchases", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.bigint "outlet_id"
    t.bigint "staff_id"
    t.integer "amount", default: 0, null: false
    t.integer "points_earned", default: 0, null: false
    t.string "source", default: "staff_scan", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "voided_at"
    t.string "void_reason"
    t.bigint "voided_by_id"
    t.string "idempotency_key"
    t.index ["member_id"], name: "index_purchases_on_member_id"
    t.index ["outlet_id"], name: "index_purchases_on_outlet_id"
    t.index ["staff_id"], name: "index_purchases_on_staff_id"
    t.index ["voided_by_id"], name: "index_purchases_on_voided_by_id"
    t.index ["workspace_id", "created_at"], name: "index_purchases_on_workspace_id_and_created_at"
    t.index ["workspace_id", "idempotency_key"], name: "index_purchases_on_workspace_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["workspace_id", "voided_at"], name: "index_purchases_on_workspace_id_and_voided_at"
    t.index ["workspace_id"], name: "index_purchases_on_workspace_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id", "endpoint"], name: "index_push_subscriptions_on_member_id_and_endpoint", unique: true
    t.index ["member_id"], name: "index_push_subscriptions_on_member_id"
    t.index ["workspace_id"], name: "index_push_subscriptions_on_workspace_id"
  end

  create_table "ratings", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.bigint "outlet_id"
    t.integer "stars", default: 5, null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "reply_body"
    t.datetime "replied_at"
    t.bigint "replied_by_id"
    t.index ["member_id"], name: "index_ratings_on_member_id"
    t.index ["outlet_id"], name: "index_ratings_on_outlet_id"
    t.index ["replied_by_id"], name: "index_ratings_on_replied_by_id"
    t.index ["workspace_id", "member_id"], name: "index_ratings_on_workspace_id_and_member_id"
    t.index ["workspace_id"], name: "index_ratings_on_workspace_id"
  end

  create_table "referrals", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "referrer_id", null: false
    t.bigint "referred_id", null: false
    t.string "state", default: "pending", null: false
    t.integer "reward_points", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["referred_id"], name: "index_referrals_on_referred_id", unique: true
    t.index ["referrer_id"], name: "index_referrals_on_referrer_id"
    t.index ["workspace_id", "referrer_id"], name: "index_referrals_on_workspace_id_and_referrer_id"
    t.index ["workspace_id"], name: "index_referrals_on_workspace_id"
  end

  create_table "rewards", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "kind", default: "voucher", null: false
    t.string "icon"
    t.integer "cost_points"
    t.integer "value", default: 0, null: false
    t.string "value_unit", default: "vnd", null: false
    t.text "terms"
    t.integer "stock"
    t.integer "redeemed_count", default: 0, null: false
    t.integer "valid_days", default: 30, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_at"
    t.jsonb "schedule", default: {}, null: false
    t.datetime "expires_at"
    t.index ["workspace_id", "active", "position"], name: "index_rewards_on_workspace_id_and_active_and_position"
    t.index ["workspace_id", "archived_at"], name: "index_rewards_on_workspace_id_and_archived_at"
    t.index ["workspace_id"], name: "index_rewards_on_workspace_id"
  end

  create_table "spin_logs", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.integer "segment_index"
    t.string "result_kind"
    t.integer "result_value", default: 0, null: false
    t.integer "cost", default: 0, null: false
    t.bigint "voucher_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id", "created_at"], name: "index_spin_logs_on_member_id_and_created_at"
    t.index ["member_id"], name: "index_spin_logs_on_member_id"
    t.index ["voucher_id"], name: "index_spin_logs_on_voucher_id"
    t.index ["workspace_id"], name: "index_spin_logs_on_workspace_id"
  end

  create_table "spin_wheels", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.jsonb "segments", default: [], null: false
    t.boolean "daily_free", default: true, null: false
    t.integer "cost_points", default: 100, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id"], name: "index_spin_wheels_on_workspace_id", unique: true
  end

  create_table "stamp_card_memberships", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.bigint "stamp_card_id", null: false
    t.integer "count", default: 0, null: false
    t.integer "completed_count", default: 0, null: false
    t.datetime "last_stamp_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id", "stamp_card_id"], name: "index_stamp_card_memberships_on_member_id_and_stamp_card_id", unique: true
    t.index ["member_id"], name: "index_stamp_card_memberships_on_member_id"
    t.index ["stamp_card_id"], name: "index_stamp_card_memberships_on_stamp_card_id"
    t.index ["workspace_id"], name: "index_stamp_card_memberships_on_workspace_id"
  end

  create_table "stamp_cards", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "reward_id"
    t.string "title", null: false
    t.text "description"
    t.string "icon"
    t.integer "target_count", default: 10, null: false
    t.boolean "active", default: true, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reward_id"], name: "index_stamp_cards_on_reward_id"
    t.index ["workspace_id"], name: "index_stamp_cards_on_workspace_id"
  end

  create_table "tiers", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "threshold_points", default: 0, null: false
    t.decimal "multiplier", precision: 4, scale: 2, default: "1.0", null: false
    t.jsonb "benefits", default: [], null: false
    t.string "gradient_from"
    t.string "gradient_to"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "key"], name: "index_tiers_on_workspace_id_and_key", unique: true
    t.index ["workspace_id", "position"], name: "index_tiers_on_workspace_id_and_position"
    t.index ["workspace_id"], name: "index_tiers_on_workspace_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", default: "", null: false
    t.string "title"
    t.string "phone"
    t.string "locale", default: "vi", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "vouchers", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.bigint "member_id", null: false
    t.bigint "reward_id", null: false
    t.string "code", null: false
    t.string "source", default: "redeem", null: false
    t.string "state", default: "active", null: false
    t.integer "points_spent", default: 0, null: false
    t.datetime "expires_at"
    t.string "redeem_token"
    t.datetime "redeem_token_expires_at"
    t.datetime "used_at"
    t.bigint "used_outlet_id"
    t.bigint "used_by_staff_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id", "state"], name: "index_vouchers_on_member_id_and_state"
    t.index ["member_id"], name: "index_vouchers_on_member_id"
    t.index ["reward_id"], name: "index_vouchers_on_reward_id"
    t.index ["used_by_staff_id"], name: "index_vouchers_on_used_by_staff_id"
    t.index ["used_outlet_id"], name: "index_vouchers_on_used_outlet_id"
    t.index ["workspace_id", "code"], name: "index_vouchers_on_workspace_id_and_code", unique: true
    t.index ["workspace_id", "redeem_token"], name: "index_vouchers_on_workspace_id_and_redeem_token"
    t.index ["workspace_id"], name: "index_vouchers_on_workspace_id"
  end

  create_table "workspace_insights", force: :cascade do |t|
    t.bigint "workspace_id", null: false
    t.string "kind", null: false
    t.text "body"
    t.datetime "range_from"
    t.datetime "range_to"
    t.datetime "generated_at"
    t.string "status", default: "ready", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workspace_id", "kind"], name: "index_workspace_insights_on_workspace_id_and_kind", unique: true
    t.index ["workspace_id"], name: "index_workspace_insights_on_workspace_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "subdomain", null: false
    t.string "custom_domain"
    t.datetime "domain_verified_at"
    t.string "industry", default: "fnb", null: false
    t.string "status", default: "trial", null: false
    t.string "plan", default: "starter", null: false
    t.string "locale_default", default: "vi", null: false
    t.jsonb "theme", default: {}, null: false
    t.jsonb "branding", default: {}, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "paid_until"
    t.boolean "auto_renew", default: false, null: false
    t.index ["custom_domain"], name: "index_workspaces_on_custom_domain", unique: true, where: "(custom_domain IS NOT NULL)"
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
    t.index ["status"], name: "index_workspaces_on_status"
    t.index ["subdomain"], name: "index_workspaces_on_subdomain", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "badges", "rewards"
  add_foreign_key "badges", "workspaces"
  add_foreign_key "broadcasts", "campaigns"
  add_foreign_key "broadcasts", "users", column: "created_by_id"
  add_foreign_key "broadcasts", "workspaces"
  add_foreign_key "campaigns", "rewards"
  add_foreign_key "campaigns", "workspaces"
  add_foreign_key "invoices", "workspaces"
  add_foreign_key "loyalty_programs", "workspaces"
  add_foreign_key "member_badges", "badges"
  add_foreign_key "member_badges", "members"
  add_foreign_key "member_badges", "workspaces"
  add_foreign_key "members", "members", column: "referred_by_id"
  add_foreign_key "members", "workspaces"
  add_foreign_key "memberships", "outlets"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "workspaces"
  add_foreign_key "merchant_alerts", "workspaces"
  add_foreign_key "mission_progresses", "members"
  add_foreign_key "mission_progresses", "missions"
  add_foreign_key "mission_progresses", "workspaces"
  add_foreign_key "missions", "workspaces"
  add_foreign_key "notifications", "broadcasts"
  add_foreign_key "notifications", "members"
  add_foreign_key "notifications", "workspaces"
  add_foreign_key "otp_challenges", "workspaces"
  add_foreign_key "outlets", "workspaces"
  add_foreign_key "point_transactions", "members"
  add_foreign_key "point_transactions", "outlets"
  add_foreign_key "point_transactions", "users", column: "staff_id"
  add_foreign_key "point_transactions", "workspaces"
  add_foreign_key "pos_charges", "members"
  add_foreign_key "pos_charges", "outlets"
  add_foreign_key "pos_charges", "purchases"
  add_foreign_key "pos_charges", "users", column: "staff_id"
  add_foreign_key "pos_charges", "workspaces"
  add_foreign_key "promo_claims", "members"
  add_foreign_key "promo_claims", "promo_codes"
  add_foreign_key "promo_claims", "vouchers"
  add_foreign_key "promo_claims", "workspaces"
  add_foreign_key "promo_codes", "campaigns"
  add_foreign_key "promo_codes", "rewards"
  add_foreign_key "promo_codes", "workspaces"
  add_foreign_key "purchases", "members"
  add_foreign_key "purchases", "outlets"
  add_foreign_key "purchases", "users", column: "staff_id"
  add_foreign_key "purchases", "users", column: "voided_by_id"
  add_foreign_key "purchases", "workspaces"
  add_foreign_key "push_subscriptions", "members"
  add_foreign_key "push_subscriptions", "workspaces"
  add_foreign_key "ratings", "members"
  add_foreign_key "ratings", "outlets"
  add_foreign_key "ratings", "users", column: "replied_by_id"
  add_foreign_key "ratings", "workspaces"
  add_foreign_key "referrals", "members", column: "referred_id"
  add_foreign_key "referrals", "members", column: "referrer_id"
  add_foreign_key "referrals", "workspaces"
  add_foreign_key "rewards", "workspaces"
  add_foreign_key "spin_logs", "members"
  add_foreign_key "spin_logs", "vouchers"
  add_foreign_key "spin_logs", "workspaces"
  add_foreign_key "spin_wheels", "workspaces"
  add_foreign_key "stamp_card_memberships", "members"
  add_foreign_key "stamp_card_memberships", "stamp_cards"
  add_foreign_key "stamp_card_memberships", "workspaces"
  add_foreign_key "stamp_cards", "rewards"
  add_foreign_key "stamp_cards", "workspaces"
  add_foreign_key "tiers", "workspaces"
  add_foreign_key "vouchers", "members"
  add_foreign_key "vouchers", "outlets", column: "used_outlet_id"
  add_foreign_key "vouchers", "rewards"
  add_foreign_key "vouchers", "users", column: "used_by_staff_id"
  add_foreign_key "vouchers", "workspaces"
  add_foreign_key "workspace_insights", "workspaces"
end
