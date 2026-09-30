# Quenly

Nền tảng **Loyalty-as-a-Service** cho cửa hàng vừa và nhỏ ở Việt Nam (F&B, bán lẻ, dịch vụ).
Mỗi cửa hàng đăng ký là có ngay một **app tích điểm mang thương hiệu riêng** cho khách của mình:
tích điểm bằng QR tại quầy, đổi quà, hạng thành viên, thẻ tem, nhiệm vụ, vòng quay, chiến dịch
và thông báo đẩy. Không cần thẻ cứng, khách không cần cài app (PWA chạy trên trình duyệt).

Mô tả tính năng chi tiết: [docs/TINH-NANG.md](docs/TINH-NANG.md).

## Một codebase, bốn bề mặt

| App | Ai dùng | Truy cập | Đăng nhập |
|---|---|---|---|
| **Landing** | Khách tiềm năng (chủ shop) | Host gốc, ví dụ `quenly.tiumpower.com` | — |
| **Customer PWA** | Khách của cửa hàng | `<shop>.quenly.tiumpower.com` · dev: `/w/<slug>` hoặc `<shop>.lvh.me:3000` | Email + OTP |
| **Merchant** | Chủ shop, quản lý, thu ngân | `/merchant` | Email + mật khẩu |
| **Super Admin** | Vận hành nền tảng | `/admin` | Tài khoản admin riêng |

Mỗi cửa hàng là một **Workspace** (multi-tenant qua `acts_as_tenant`): dữ liệu, thương hiệu,
subdomain và chương trình loyalty tách biệt hoàn toàn.

## Tính năng chính

- **Tích điểm tại quầy**: nhân viên quét QR cá nhân của khách (xoay mỗi 2 phút), hoặc khách quét QR hoá đơn.
- **4 cơ chế loyalty**: điểm · hạng thành viên · thẻ tem · gamification (nhiệm vụ, huy hiệu, vòng quay).
- **Đổi quà**: đổi điểm lấy voucher, dùng bằng mã một lần có hạn 12 phút, kiểm soát tồn kho.
- **Chiến dịch & CRM**: phân nhóm khách, gửi thông báo đẩy, mã QR khuyến mãi, banner tạo bằng AI.
- **Giới thiệu bạn bè**, đánh giá cửa hàng, tự động hoá (chào mừng, sinh nhật…).
- **Báo cáo**: khách mới, doanh thu, điểm phát ra/đã đổi, giờ cao điểm (AI gợi ý).
- **Thu phí thuê bao** qua PayOS, có dùng thử, ân hạn và tự tạm ngưng khi quá hạn.
- Song ngữ **Việt / Anh**.

### Gói cước (mặc định trong `Plan::DEFAULTS`)

| Gói | Giá/tháng | Chi nhánh | Khách | Mở khoá thêm |
|---|---|---|---|---|
| Starter | 199.000đ | 1 | 500 | Điểm, hạng, thẻ tem |
| Growth | 499.000đ | 5 | Không giới hạn | Gamification, chiến dịch |
| Scale | 1.290.000đ | Không giới hạn | Không giới hạn | Tên miền riêng, A/B test |

## Stack

Rails 7.2 · Ruby 3.2.2 · PostgreSQL · Redis · Sidekiq + sidekiq-cron · Hotwire (Turbo/Stimulus)
· Tailwind · importmap · Devise · Active Storage (DigitalOcean Spaces) · Web Push · Sentry.

## Chạy ở máy local

Cần: Ruby 3.2.2 (qua rbenv), PostgreSQL, Redis đang chạy.

```bash
gem install bundler:2.4.10
bundle install
bin/rails db:prepare   # tạo DB, nạp schema và dữ liệu demo
bin/dev                # Rails server + Tailwind watch → http://localhost:3000
```

Tài khoản demo (mật khẩu `loyalty1234`):

| Vào | Tài khoản |
|---|---|
| `localhost:3000/admin` | `admin@loyalty.vn` |
| `localhost:3000/merchant` | `owner@cozycafe.vn` (cũng có `owner@luaspa.vn`, `owner@phoretail.vn`) |
| `cozycafe.lvh.me:3000` | Nhập email bất kỳ; ở dev mã OTP hiện ngay trên màn hình |

Job nền (hết hạn điểm, gia hạn thuê bao, gửi thông báo hẹn giờ) chạy bằng `bundle exec sidekiq`.

## Biến môi trường

Đặt trong `.env` (đọc bằng dotenv). Ở local không bắt buộc biến nào; thiếu biến nào thì tính năng tương ứng tự tắt.

| Nhóm | Biến |
|---|---|
| Cơ bản | `RAILS_MASTER_KEY`, `PLATFORM_HOST`, `REDIS_URL`, `LOYALTY_DATABASE_PASSWORD` |
| Email (OTP, hoá đơn) | `BREVO_API_KEY` hoặc `SMTP_ADDRESS/PORT/USERNAME/PASSWORD/DOMAIN`; `MAIL_FROM`, `MAIL_FROM_NAME` |
| Thanh toán PayOS | `PAYOS_CLIENT_ID`, `PAYOS_API_KEY`, `PAYOS_CHECKSUM_KEY` |
| Thông báo đẩy | `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` |
| AI | `ANTHROPIC_API_KEY` (nội dung, màu theme, duyệt ảnh nhiệm vụ, insight) · `OPENAI_API_KEY` (banner) |
| Lưu file | `SPACES_KEY`, `SPACES_SECRET`, `SPACES_BUCKET`, `SPACES_REGION`, `SPACES_ENDPOINT`, `SPACES_PREFIX` |
| Giám sát | `SENTRY_DSN`, `SENTRY_TRACES_RATE` |

> ⚠️ Ở production **phải** cấu hình email. Nếu thiếu, mã OTP sẽ hiện trên màn hình
> và bất kỳ ai cũng đăng nhập được vào tài khoản khách.

## Test

```bash
bin/rails test        # unit + integration
bin/brakeman          # quét bảo mật
bin/rubocop           # lint
```

CI (GitHub Actions) chạy cả ba trên mỗi PR.

## Deploy

Capistrano lên VPS (Puma + Sidekiq qua systemd), file `.env` nằm ở thư mục shared trên server.

```bash
bundle exec cap production deploy            # nhánh main
BRANCH=feature-x bundle exec cap production deploy
```

## Cấu trúc thư mục đáng chú ý

| Đường dẫn | Nội dung |
|---|---|
| `app/controllers/{customer,merchant,admin}/` | Ba app tương ứng |
| `app/services/` | Nghiệp vụ: `EarnPoints`, `RedeemReward`, `VoidPurchase`, `Gamification`, `Referrals`… |
| `app/views/customer/home/landing.html.erb` | Landing page (layout `layouts/marketing`) |
| `config/locales/{vi,en}.yml` | Toàn bộ chữ hiển thị |
| `db/seeds.rb` | Dữ liệu demo |
