# Gửi OTP đăng nhập qua Zalo

Khách đăng nhập vào PWA bằng **số điện thoại**, mã xác thực 6 số gửi qua Zalo.
Có hai đường gửi, chọn bằng biến môi trường — code giống nhau, chỉ khác nhà
cung cấp:

| Đường | Khi nào chọn | Chi phí | Việc phải làm trước |
|---|---|---|---|
| `zns` — Zalo OA của mình | dùng lâu dài | rẻ nhất / tin | đăng ký OA + ZCA + duyệt template (vài ngày) |
| `esms` — qua đại lý eSMS | cần chạy ngay | cao hơn | mở tài khoản eSMS, nhờ họ đăng ký template |

**Chưa cấu hình gì thì tính năng vẫn chạy**: mã OTP hiện thẳng trên màn hình
đăng nhập. Đủ để demo, nhưng **ai biết số điện thoại của một khách cũng đăng
nhập được vào tài khoản đó** — xem phần cuối về việc phải tắt.

---

## Đường A — Zalo OA của mình (ZNS)

ZNS (Zalo Notification Service) gửi tin theo **template đã được Zalo duyệt** từ
một Official Account. Template OTP là loại được duyệt nhanh nhất vì nội dung
cố định.

1. **Tạo Zalo Official Account** tại `oa.zalo.me`, rồi **xác thực OA** (cần giấy
   phép kinh doanh). OA chưa xác thực không gửi được ZNS.
2. **Tạo Zalo Cloud Account (ZCA)** tại `zcloud.vn` và **nạp tiền**. ZNS trừ
   tiền theo từng tin; hết số dư là ngừng gửi (và `delivery_error` sẽ nói vậy).
3. **Tạo ứng dụng** tại `developers.zalo.me`, bật sản phẩm ZNS, rồi **liên kết
   OA** ở trên vào ứng dụng đó. Lấy `App ID` và `App Secret Key`.
4. **Đăng ký template OTP** trong ZCA và chờ duyệt. Template chỉ cần một tham
   số là mã OTP. **Ghi lại tên tham số đó** — nếu không phải `otp` thì phải đặt
   `ZALO_ZNS_OTP_PARAM` cho khớp, nếu không Zalo trả lỗi tham số.
5. **Lấy refresh token lần đầu.** Code trong app chỉ biết *làm mới* token, không
   biết xin token đầu tiên — bước này làm tay một lần:

   a. Mở link cấp quyền trong trình duyệt (thay `APP_ID` và `REDIRECT_URI` đã
      khai trong ứng dụng), đăng nhập bằng tài khoản quản trị OA:

   ```
   https://oauth.zaloapp.com/v4/oa/permission?app_id=APP_ID&redirect_uri=REDIRECT_URI
   ```

   b. Zalo chuyển về `REDIRECT_URI?code=...`. Đổi `code` đó thành cặp token:

   ```bash
   curl -X POST https://oauth.zaloapp.com/v4/oa/access_token \
     -H "secret_key: APP_SECRET" \
     -d "code=CODE_VUA_NHAN&app_id=APP_ID&grant_type=authorization_code"
   ```

   c. Lấy `refresh_token` trong kết quả, đặt vào `ZALO_OA_REFRESH_TOKEN`.

   > Nếu Zalo đổi luồng OAuth, làm theo tài liệu hiện hành của họ — phần còn
   > lại của app không phụ thuộc vào bước này.

6. Đặt biến môi trường (xem bảng dưới) rồi **gửi thử** ở `/admin/settings`.

**Quan trọng về refresh token:** Zalo **thu hồi token cũ sau mỗi lần làm mới**.
App lưu token mới vào bảng `app_settings`, nên giá trị trong `.env` sẽ cũ đi sau
lần làm mới đầu tiên — đó là bình thường, và cũng là lý do trang
`/admin/settings` có ô dán refresh token mới mà không cần deploy. App giữ lại
token vừa bị thay ở khoá `zns_refresh_token_prev` để còn đường cứu nếu bị đè.

---

## Đường B — qua đại lý eSMS

eSMS giữ quan hệ với Zalo; mình chỉ đưa template id và mã OTP.

1. Mở tài khoản tại `esms.vn`, nạp tiền.
2. Nhờ eSMS **đăng ký một template ZNS dạng OTP** dưới OA của họ (hoặc OA của
   mình nếu đã có). Họ trả về `TempID` và `OAID`.
3. Lấy `ApiKey` và `SecretKey` trong trang quản trị eSMS.
4. Đặt biến môi trường rồi **gửi thử** ở `/admin/settings`.

Endpoint dùng là `SendZaloMessage_V6`, nghĩa là **mình vẫn tự sinh mã** và tự
xác thực. Endpoint tự-sinh-mã đa kênh của eSMS *không* được dùng: nó sinh mã
phía họ, mình sẽ mất quyền hết hạn và giới hạn số lần nhập sai.

---

## Biến môi trường

Đặt trong `.env` (dev) hoặc `shared/.env` trên server (production). **Giá trị có
dấu cách phải bọc ngoặc kép.**

```bash
# Chọn đường gửi. Để trống = tự dò (ưu tiên zns). "none" = tắt cứng.
OTP_ZALO_PROVIDER=            # zns | esms | none
OTP_PROVIDER_FALLBACK=true    # gửi lỗi thì thử nhà cung cấp còn lại

# Đường A — Zalo OA của mình
ZALO_APP_ID=
ZALO_APP_SECRET=
ZALO_ZNS_TEMPLATE_ID=
ZALO_OA_REFRESH_TOKEN=        # chỉ cần lần đầu; sau đó app tự quản trong DB
ZALO_ZNS_OTP_PARAM=otp        # tên tham số OTP trong template, nếu khác "otp"

# Đường B — đại lý eSMS
ESMS_API_KEY=
ESMS_SECRET_KEY=
ESMS_OA_ID=
ESMS_TEMPLATE_ID=
ESMS_OTP_PARAM=otp
ESMS_CAMPAIGN_ID=             # tuỳ chọn, để lọc báo cáo bên eSMS
ESMS_SANDBOX=false            # true = chế độ thử của eSMS, không gửi thật
```

Đổi khoá xong **phải restart cả web lẫn sidekiq** — việc gửi chạy trong job nên
chỉ restart puma là sidekiq vẫn dùng khoá cũ.

---

## Kiểm chứng

1. Vào `/admin/settings` → panel **Cổng gửi OTP qua Zalo**. Panel nói rõ biến nào
   còn thiếu.
2. Nhập số của chính bạn, bấm **Gửi thử**. Tốn một tin như bình thường.
3. Gửi thành công một lần là app ghi mốc `zns_verified_at` và **từ đó tự chuyển
   OTP của khách sang Zalo**. Trước mốc đó, khách nào đã khai email vẫn nhận mã
   qua email — cố ý như vậy, để việc cắm biến môi trường không lấy đi một kênh
   đang chạy tốt và thay bằng kênh chưa chứng minh được.
4. Thử đăng nhập thật bằng PWA khách.

Gửi lỗi thì lỗi được ghi vào `otp_challenges.delivery_error` và hiện cho khách
một dòng giải thích kèm đường đi tiếp — **mã KHÔNG bao giờ bị hiện ra vì gửi
lỗi** (nếu không, một lần nhà cung cấp sập sẽ thành lỗ đăng nhập cho mọi tài
khoản).

---

## Tắt chế độ hiện mã trên màn hình

Chừng nào chưa có cổng gửi, mã OTP hiện thẳng trên màn hình đăng nhập để tính
năng còn dùng được. **Phải tắt trước khi có người dùng thật.**

- Mã chỉ hiện khi: đang ở môi trường dev, HOẶC người vận hành bật cờ ở
  `/admin/settings`, HOẶC **không có kênh nào gửi được**.
- Nghĩa là: cấu hình xong cổng Zalo và tắt cờ → mã không còn hiện ở đâu nữa.

---

## Giới hạn cần biết

- **ZNS chỉ tới được số đã dùng Zalo.** Số không có Zalo sẽ lỗi; khách đã khai
  email thì màn xác thực mời họ nhận mã qua email, còn lại cần một kênh SMS
  (chưa nối) hoặc nhờ nhân viên hỗ trợ.
- **Mỗi tin mất tiền**, nên `Rack::Attack` chặn 5 lần/10 phút theo từng số,
  20 lần/10 phút theo IP và 60 lần/giờ theo từng workspace. Đây chính là nắp
  chi phí, đừng nới mà không tính lại tiền.
- **Một OA dùng chung cho mọi workspace.** Tin ZNS mang thương hiệu OA của nền
  tảng, không phải tên từng cửa hàng. Muốn mỗi khách hàng một OA riêng thì cần
  chuyển cấu hình nhà cung cấp xuống cấp workspace — `OtpSender` đã tách thành
  adapter nên thêm được, nhưng hiện chưa làm.
