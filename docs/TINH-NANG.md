# Dynamic Loyalty — Tài liệu mô tả tính năng

> Nền tảng **Loyalty-as-a-Service** đa workspace (multi-tenant) cho chuỗi F&B / bán lẻ / dịch vụ.
> Một lần cài, phục vụ nhiều cửa hàng; mỗi cửa hàng có tên miền, bộ nhận diện, chương trình
> tích điểm và dữ liệu riêng biệt.
>
> Stack: Ruby on Rails 7.2 · PostgreSQL · Sidekiq · Hotwire (Turbo/Stimulus) · PWA · acts_as_tenant.
> Ngôn ngữ giao diện: **Tiếng Việt / English** (chuyển đổi tại chỗ).

---

## 1. Tổng quan

Hệ thống gồm **ba ứng dụng** chạy chung một codebase, phân tách bằng host và namespace:

| Ứng dụng | Người dùng | Đường dẫn | Đăng nhập |
|---|---|---|---|
| **Customer PWA** | Khách hàng cuối | `shop.loyalty.tiumpower.com` (hoặc `/w/:slug` khi dev) | Email + mã OTP |
| **Merchant Dashboard** | Chủ shop, quản lý, thu ngân | `/merchant` | Email + mật khẩu (Devise) |
| **Super Admin** | Vận hành nền tảng | `/admin` | Tài khoản admin riêng (Devise) |

### 1.1. Mô hình nhiều cửa hàng (multi-tenant)

- Mỗi cửa hàng là một **Workspace**: có `subdomain` riêng, tùy chọn `custom_domain`, slug thân thiện.
- Mọi bảng dữ liệu nghiệp vụ đều gắn `workspace_id` và được cô lập tự động bằng `acts_as_tenant`
  — khách của shop A không tồn tại ở shop B, kể cả trùng email.
- Workspace resolve theo thứ tự: **custom domain → subdomain → `/w/:slug`**. Host gốc của nền tảng
  hiển thị trang giới thiệu bán hàng (landing + bảng giá).
- Trạng thái workspace: `pending` (chờ duyệt) · `trial` (dùng thử) · `active` · `past_due` (quá hạn) · `suspended`.

---

## 2. Ứng dụng Khách hàng (Customer PWA)

Giao diện mobile-first, cài được lên màn hình chính như một app (manifest + service worker + icon
sinh động theo từng shop), toàn bộ màu sắc/phông chữ lấy theo thương hiệu của shop.

### 2.1. Đăng nhập & tài khoản

- **Đăng nhập bằng email + OTP**, không cần mật khẩu. Lần đăng nhập đầu tiên tự tạo hồ sơ khách.
- OTP gửi qua email (Brevo/SMTP). Khi chưa cấu hình nhà cung cấp, mã hiện trực tiếp trên màn hình
  (dùng cho môi trường test — Super Admin có công tắc bật/tắt).
- Phiên đăng nhập là **cookie dài hạn theo từng shop** — khách không phải đăng nhập lại mỗi lần ghé.
- Hồ sơ: tên, email, ngày sinh, giới tính, ảnh đại diện, ngôn ngữ.
- **Đổi email phải xác thực**: email chính là danh tính đăng nhập, nên địa chỉ mới phải nhập mã
  gửi tới chính nó trước khi thay thế — tránh gõ sai làm mất toàn bộ điểm.

### 2.2. Trang chủ

- Thẻ thành viên: số điểm hiện có, hạng, tiến độ lên hạng kế tiếp.
- Ưu đãi nổi bật đang mở đổi (và sắp mở, xếp sau).
- Nhiệm vụ đang làm dở được ưu tiên hiển thị trước nhiệm vụ đã hoàn thành.
- Badge số thông báo chưa đọc.

### 2.3. Ví ưu đãi (Wallet)

- **Danh mục quà**: danh sách ưu đãi shop phát hành — sắp theo trạng thái *đang mở → sắp mở →
  ngoài khung giờ → hết hàng*, ẩn ưu đãi đã kết thúc.
- **Đổi điểm lấy voucher**: kiểm tra tồn kho, khung thời gian, số điểm; trừ điểm và phát voucher
  trong cùng một giao dịch có khóa hàng (không thể đổi trùng khi bấm hai lần).
- **Voucher của tôi**: tách rõ *khả dụng* (sắp hết hạn lên đầu) và *lịch sử* (đã dùng/hết hạn).
- Loại ưu đãi: `voucher` · `gift` (quà tặng) · `discount`; đơn vị giá trị: VNĐ, %, hoặc món.
- Ưu đãi hỗ trợ: điểm đổi, tồn kho, hạn dùng voucher (số ngày), khung ngày chạy, **lịch theo
  khung giờ/ngày trong tuần** (ví dụ "chỉ đổi được 14h–17h thứ 2–6").

### 2.4. Sử dụng voucher tại quầy

- Khách bấm "Dùng ngay" → app sinh **mã dùng một lần 10 chữ số + QR**, có đếm ngược thời gian sống.
- Nhân viên quét/nhập mã ở màn hình *Xác thực ưu đãi* → voucher chuyển sang `used`, ghi nhận
  chi nhánh + nhân viên xác thực.
- Màn hình của khách **tự động chuyển sang "đã dùng"** ngay khi quầy xác thực (polling trạng thái).

### 2.5. Mã QR cá nhân (tích điểm tại quầy)

- Màn hình "Mã của tôi" hiển thị QR **ký số, tự hết hạn sau 120 giây** và tự làm mới — ảnh chụp
  màn hình không thể dùng lại ở quầy khác.
- Sau khi nhân viên tích điểm, điện thoại khách tự hiện hiệu ứng "+X điểm" và số dư mới.

### 2.6. Quét mã (Scan)

Một camera duy nhất trong app xử lý được mọi loại mã của hệ thống:

| Loại mã | Tác dụng |
|---|---|
| **QR check-in tại cửa hàng** | Điểm danh có mặt (1 lần/ngày), hoàn thành nhiệm vụ check-in và nhận điểm |
| **QR khuyến mãi (promo)** | Nhận ngay voucher của chiến dịch vào ví |
| **QR hóa đơn POS** | Khách tự quét mã hóa đơn để cộng điểm (luồng dự phòng) |

### 2.7. Hạng thành viên (Tiers)

- Mặc định 4 hạng: **Đồng · Bạc · Vàng · Kim Cương**, ngưỡng điểm và **hệ số nhân điểm** riêng
  (1.0 → 2.0), màu gradient riêng, danh sách quyền lợi tự khai báo.
- Hạng tính theo **điểm tích lũy trong chu kỳ** (mặc định 12 tháng), nên khách phải duy trì chi tiêu
  để giữ hạng.
- Màn hình hạng cho khách xem: hạng hiện tại, quyền lợi, còn bao nhiêu điểm để lên hạng.

### 2.8. Trò chơi hóa (Gamification)

- **Thẻ tem (Stamp cards)** — "mua 10 tặng 1": mỗi hóa đơn cộng 1 tem, đủ mục tiêu thì tự phát quà
  và làm mới thẻ. Nếu quà hết hàng, thẻ **giữ nguyên trạng thái đầy** và tự trả thưởng ngay khi
  shop nhập hàng lại (khách không mất thẻ).
- **Nhiệm vụ (Missions)** — loại: `checkin`, `spend` (chi tiêu), `visit` (số lần ghé), `refer`
  (giới thiệu), `review` (đánh giá Google), `social_share` (chia sẻ Facebook/Instagram/TikTok/Zalo).
  Chu kỳ: hằng ngày / hằng tuần / một lần. Mỗi nhiệm vụ có mốc mục tiêu và điểm thưởng riêng
  (riêng social share có thể trả điểm khác nhau theo từng nền tảng).
- **Nhiệm vụ nộp ảnh chứng minh**: khách chụp màn hình bài đánh giá/chia sẻ → **AI (Claude vision)
  tự kiểm tra ảnh**, tự duyệt khi đủ tin cậy, tự từ chối khi chắc chắn sai, còn lại đẩy vào
  hàng đợi duyệt tay cho shop.
- **Huy hiệu (Badges)** — điều kiện: hóa đơn đầu tiên, số lần mua, tổng điểm tích lũy, "cú đêm"
  (mua sau 22h). Có thể kèm điểm thưởng và/hoặc voucher khi đạt.
- **Vòng quay may mắn (Spin wheel)** — các ô phần thưởng tùy biến (điểm / voucher / chúc may mắn)
  với **trọng số xác suất**, một lượt quay miễn phí mỗi ngày, các lượt sau trả bằng điểm.
  Quay có khóa hàng: không thể ăn gian bằng cách bấm hai lần, và quà là voucher vẫn trừ tồn kho thật.

### 2.9. Giới thiệu bạn bè (Referral)

- Mỗi khách có **mã giới thiệu + link/QR chia sẻ** riêng.
- Người được giới thiệu đăng ký qua link → tạo liên kết `pending`; **khi họ mua hàng lần đầu**,
  cả hai bên cùng được cộng điểm (số điểm do shop cấu hình).
- Chỉ áp dụng cho khách **mới** — khách cũ quét mã của chính shop mình sẽ nhận thông báo rõ ràng.

### 2.10. Thông báo

- Hộp thư trong app (khuyến mãi, quà nhận được, nhắc điểm sắp hết hạn, trả lời đánh giá…),
  có đánh dấu đã đọc / đọc tất cả, deep-link vào đúng màn hình liên quan.
- **Web Push (PWA)**: khách bật nhận thông báo đẩy trên điện thoại; hệ thống gửi qua VAPID.

### 2.11. Đánh giá & trang giới thiệu shop

- Trang "Về cửa hàng": thông tin shop, danh sách chi nhánh, điểm trung bình và **tường đánh giá
  công khai** (shop có thể tắt).
- Khách chấm sao + viết nhận xét, được **sửa lại đánh giá của mình**, và gửi nhiều đánh giá theo thời gian.
- Không mặc định sẵn 5 sao — tránh thổi phồng điểm trung bình.
- Đánh giá thấp có thể kích hoạt **voucher xin lỗi tự động** (có giới hạn 90 ngày/khách để chống trục lợi).
- Đánh giá cao có thể mời khách đăng luôn lên **Google Maps / Facebook** (link do shop cấu hình).

---

## 3. Ứng dụng Chủ shop (Merchant Dashboard)

### 3.1. Khởi tạo & onboarding

- **Đăng ký tự phục vụ** tại `/merchant/signup` → tạo ngay workspace kèm **14 ngày dùng thử
  đầy đủ tính năng**, không cần chờ duyệt.
- Trình hướng dẫn 4 bước: *Thương hiệu → Cơ chế tích điểm → Mời nhân viên → Hoàn tất*.
- Workspace mới được **dựng sẵn cấu hình chạy được ngay**: chương trình điểm theo ngành
  (F&B 10.000đ/điểm, bán lẻ 15.000đ, dịch vụ 20.000đ), 4 hạng thành viên, vòng quay mặc định,
  một chi nhánh chính.

### 3.2. Bảng điều khiển & phân tích

Lọc theo **khoảng thời gian** và **chi nhánh** (nhân viên bị khóa chi nhánh chỉ thấy chi nhánh mình):

- Điểm đã phát · điểm đã đổi · điểm đã hết hạn · **điểm còn tồn đọng (công nợ điểm)**.
- Tỷ lệ đổi điểm (redemption rate), số hóa đơn, doanh thu, điểm trung bình/khách.
- **Khách đang hoạt động** (có giao dịch trong cửa sổ gần đây — không tính người từng mua một lần).
- Tăng trưởng khách theo tháng, **nguồn khách mới** (tự đến / giới thiệu / chiến dịch).
- Phân bố khách theo hạng, thống kê theo từng chi nhánh, chỉ số giữ chân khách.
- **Khung giờ đông khách**: ma trận thứ × giờ + **gợi ý hành động do AI (Claude) viết bằng tiếng Việt**
  (có nút làm mới, giới hạn tần suất, chỉ quản lý trở lên). Khi không có AI, hệ thống vẫn đưa ra
  nhận định heuristic — panel không bao giờ trống.
- Cảnh báo hạn thanh toán gói dịch vụ.

### 3.3. Quầy thu ngân (Scanner)

- **Tích điểm**: quét QR khách (hoặc tra bằng email/SĐT) → nhập số tiền hóa đơn → cộng điểm theo
  tỷ lệ × hệ số hạng. Có **khóa chống cộng trùng** (idempotency key theo từng lượt quét) — bấm hai
  lần, mạng chậm hay back-resubmit đều chỉ ghi nhận một hóa đơn.
- **Xác thực ưu đãi**: quét mã dùng của voucher → xác nhận → đánh dấu đã dùng vĩnh viễn.
- **Tự định tuyến mã**: quét nhầm tab cũng chạy đúng — hệ thống tự nhận biết QR khách và mã voucher.
- **QR hóa đơn POS**: tạo QR theo số tiền để khách tự quét cộng điểm (luồng hiện đang tắt mặc định).
- **Chế độ kiosk**: giao diện tối giản cho điện thoại đặt tại quầy, không có sidebar.
- **QR đăng nhập nhanh cho nhân viên**: nhân viên quét QR từ máy chủ shop để đăng nhập trên
  điện thoại mà không phải gõ mật khẩu (token ký số, sống 2 phút).
- **QR check-in chi nhánh**: mã tĩnh để in poster; có **nút xoay mã** làm vô hiệu mọi poster cũ
  khi mã bị chụp lại và phát tán.

### 3.4. Khách hàng & phân khúc (CRM)

- Danh sách khách kèm tìm kiếm theo tên/email/SĐT, lọc theo chi nhánh và hạng, sắp xếp.
- **Phân khúc dựng sẵn**: Tất cả · VIP · Khách mới trong tuần · Có điểm chưa đổi · Sắp hoàn thành
  thẻ tem · Sinh nhật tuần này · Sinh nhật tháng này · Sắp rời bỏ (>30 ngày) · Đã rời bỏ (>60 ngày).
- Hồ sơ khách: điểm, hạng, lịch sử giao dịch, voucher, nhiệm vụ, nguồn đến.
- **Điều chỉnh điểm thủ công** (cộng/trừ, có ghi chú — quản lý trở lên).
- **Hủy hóa đơn ghi nhầm (void)**: sổ cái giữ nguyên bản ghi gốc và ghi thêm bút toán âm đối ứng;
  hóa đơn bị gắn cờ nên rơi khỏi mọi báo cáo doanh thu nhưng vẫn còn dấu vết kiểm toán.
  Tem/nhiệm vụ được hoàn lại ở mức an toàn — phần thưởng đã phát và có thể đã dùng thì không thu hồi.
- Xóa khách (chỉ chủ shop).

### 3.5. Cấu hình chương trình tích điểm

- Bật/tắt từng trụ: **điểm · hạng · thẻ tem · gamification**.
- Tỷ lệ tích điểm (X điểm cho mỗi Y đồng), đơn vị tiền tệ.
- **Hạn sử dụng điểm** (0 = không hết hạn): hệ thống tự trừ điểm quá hạn theo FIFO và
  **nhắc khách trước 7 ngày**.
- Chu kỳ tính hạng (tháng), bật/tắt referral và số điểm thưởng giới thiệu.
- Biên cứng ở mọi tham số (chống gõ nhầm làm sập chương trình, ví dụ chu kỳ hạng = 0 từng đẩy
  toàn bộ khách xuống hạng thấp nhất).

### 3.6. Ưu đãi, thẻ tem, nhiệm vụ, huy hiệu, vòng quay

- CRUD ưu đãi kèm **bật/tắt nhanh** ngay trên danh sách, ảnh, điều khoản, tồn kho, lịch phát hành.
- Ưu đãi đang được dùng (đã phát voucher, gắn thẻ tem/chiến dịch) **không cho xóa** — chỉ tắt,
  tránh làm bốc hơi voucher trong ví khách.
- Quản lý thẻ tem (mục tiêu, quà, khung thời gian, tạm dừng/chạy).
- Quản lý nhiệm vụ + **hàng đợi duyệt ảnh chứng minh** (duyệt/từ chối, kèm nhận định của AI).
- Quản lý huy hiệu và cấu hình vòng quay (nhãn, loại, giá trị, trọng số, màu, lượt miễn phí, giá điểm).

### 3.7. Chiến dịch marketing (Campaigns)

- Loại chiến dịch: **Phát voucher (QR)** · **Nhân đôi điểm** · **Giờ vàng** · **Sự kiện** ·
  **Nhiệm vụ chớp nhoáng**.
- Vòng đời: `draft → scheduled → running ⇄ paused → ended`; tạm dừng thì **QR khuyến mãi ngừng hiệu lực ngay**.
- **QR khuyến mãi** tải về dạng PNG để in poster/hóa đơn, có giới hạn tổng lượt nhận và
  giới hạn theo từng khách, đếm số lượt quét và số lượt nhận.
- **Link chia sẻ công khai** `/c/:slug` có OG preview để đăng mạng xã hội.
- **AI viết nội dung** (Claude): gợi ý tiêu đề + nội dung chiến dịch.
- **AI tạo ảnh banner** (OpenAI gpt-image): sinh banner 16:9 bất đồng bộ, có thanh tiến trình,
  và **ghép QR thật lên banner** trên thẻ trắng bo góc — ảnh chia sẻ tự nó quét được.
- **Đẩy chiến dịch tới khách**: chọn một hoặc nhiều phân khúc, hệ thống tạo broadcast và gửi đi.

### 3.8. Gửi tin & tự động hóa

- **Broadcast**: soạn tin theo phân khúc (kết hợp thêm lọc chi nhánh/hạng/từ khóa), hiển thị chính xác
  "sẽ gửi cho N khách" trùng khớp với danh sách nhìn thấy; **hẹn giờ gửi** (job chạy mỗi 5 phút),
  hủy được tin chưa gửi. Mỗi tin tạo thông báo trong app + push tới thiết bị đã đăng ký.
- **Automations "cài một lần, chạy mãi"**:
  - *Chào mừng*: tặng quà ngay khi khách đăng ký.
  - *Sinh nhật*: tự tặng quà đúng ngày sinh, mỗi năm một lần (nếu hết hàng thì không "hứa suông",
    chờ nhập hàng lại).
  - *Kéo khách quay lại (win-back)*: khách vắng mặt quá N ngày sẽ nhận tin nhắn (+ quà tùy chọn),
    có cơ chế chống làm phiền lặp lại.

### 3.9. Đánh giá & chăm sóc

- Bảng đánh giá: điểm trung bình, danh sách nhận xét theo chi nhánh.
- **Trả lời công khai từng đánh giá** — khách nhận được thông báo về câu trả lời.
- Bật/tắt tường đánh giá công khai, cấu hình link Google Review.

### 3.10. Chi nhánh, nhân sự, phân quyền

- **Chi nhánh (Outlets)**: mã, tên, địa chỉ, SĐT, bật/tắt, QR check-in riêng từng chi nhánh.
- **Nhân sự**: mời bằng email (tự tạo tài khoản nếu chưa có), gán vai trò và khóa theo chi nhánh.
- Vai trò: **owner** (toàn quyền, gồm xóa khách/đổi gói) · **manager** (quản lý vận hành) ·
  **staff / cashier** (chỉ quầy + tra cứu khách).
- Nhân viên khóa chi nhánh chỉ thấy dữ liệu và khách của chi nhánh mình.
- Một người dùng có thể thuộc nhiều workspace và **chuyển qua lại** giữa các shop.

### 3.11. Thương hiệu & giao diện (white-label)

- Tải logo (giới hạn định dạng ảnh và dung lượng 3MB), đặt tagline, cách xưng hô với khách.
- **Bộ token màu + bo góc + phông chữ** áp cho toàn bộ app khách: có sẵn preset *Cozy Cafe,
  Modern Beauty, Retail Bold…* và bộ chọn màu tùy ý.
- **AI gợi ý bảng màu từ chính logo đã tải lên** (Claude, trả về JSON màu có kiểm định).
- Mọi giá trị màu được kiểm tra định dạng hex trước khi đưa vào CSS (chặn CSS injection).
- **PWA theo từng shop**: manifest riêng, icon sinh tự động từ chữ cái đầu khi chưa có logo.
- Tên miền riêng: màn hình hướng dẫn có sẵn (hiện do đội vận hành cấu hình thủ công).

### 3.12. Gói dịch vụ & thanh toán

- Trang gói hiển thị hạn mức đang dùng, lịch sử hóa đơn, kỳ thanh toán kế tiếp.
- **Thanh toán qua PayOS** (link/QR chuyển khoản), webhook xác nhận tự động, thanh toán lại
  hóa đơn lỗi, bật **tự động gia hạn**.
- Chu kỳ tính theo **tháng dương lịch**; shop chuyển từ dùng thử sang trả phí được **tính tiền
  theo tỷ lệ ngày** của tháng đầu.
- Hết hạn: `active → past_due`, còn **10 ngày ân hạn** vẫn dùng bình thường; quá hạn thì khóa
  truy cập nhưng **luôn vào được trang thanh toán để mở lại**.
- Gói mặc định: **Starter 199.000đ · Growth 499.000đ · Scale 1.290.000đ**/tháng.

### 3.13. Hộp cảnh báo cho shop (chuông)

Chỉ báo những việc shop **làm được gì đó**, gộp trùng theo khóa, không bao giờ spam theo từng
giao dịch: đánh giá mới (nhất là đánh giá thấp), ưu đãi hết hàng, nhiệm vụ chờ duyệt, hạn thanh toán…

---

## 4. Super Admin (vận hành nền tảng)

- **Tổng quan**: số workspace, đang hoạt động / dùng thử, tổng số khách toàn nền tảng,
  tổng điểm đã phát, số workspace cần xử lý.
- **Quản lý workspace**: tạo mới (kèm tài khoản chủ shop + cấu hình mặc định theo ngành),
  duyệt, tạm ngưng, mở lại, xóa (purge sạch dữ liệu), lọc theo trạng thái và **tình trạng thanh toán**
  (Đã thanh toán · Dùng thử · Đang nợ · Tạm ngưng · Chưa có kỳ).
- **Giám sát (monitoring)**: điểm phát/đổi toàn hệ thống, số hóa đơn, voucher đã dùng,
  top workspace theo số khách, cảnh báo bất thường.
- **Doanh thu**: MRR theo gói, nhóm theo tình trạng thanh toán, danh sách hóa đơn chưa thu.
- **Quản lý gói**: sửa giá, hạn mức chi nhánh/khách, bật-tắt từng tính năng theo gói — kèm cảnh báo
  thay đổi này ảnh hưởng bao nhiêu shop và bao nhiêu khách.
- **Cài đặt nền tảng**: công tắc *hiện mã OTP trên màn hình* để phục vụ test, bật/tắt ngay không cần deploy.

---

## 5. Ma trận gói (feature gating)

Hạn mức và khóa tính năng được kiểm tra ở cả tầng controller lẫn hiển thị:

| Gate | Ý nghĩa |
|---|---|
| `max_outlets` | Số chi nhánh tối đa |
| `max_members` | Số khách tối đa (vượt trần thì chặn tạo khách mới, có thông báo lịch sự cho khách) |
| `allow_stamps` | Thẻ tem |
| `allow_gamification` | Nhiệm vụ / huy hiệu / vòng quay |
| `allow_campaigns` | Chiến dịch marketing |
| `allow_custom_domain` | Tên miền riêng |
| `allow_ab_testing` | A/B testing |

> Trong **14 ngày dùng thử, shop được mở khóa toàn bộ tính năng và không bị giới hạn hạn mức**,
> để đánh giá đầy đủ trước khi chọn gói.

---

## 6. Nền tảng & chất lượng vận hành

### 6.1. An toàn dữ liệu và chống gian lận

- **Cô lập tenant** ở tầng ORM cho mọi truy vấn nghiệp vụ.
- **Token ký số có hạn** cho: QR khách (120s), QR đăng nhập nhân viên (2 phút),
  mã dùng voucher (một lần), QR check-in (mã tĩnh nhưng xoay được).
- **Idempotency**: chỉ mục duy nhất trên `purchases` đảm bảo một lượt quét = một hóa đơn.
- **Khóa hàng + đọc lại số dư từ sổ cái** khi đổi quà, quay vòng quay, check-in — không tin
  vào cột đệm, không cho hai thao tác song song tiêu cùng một số điểm.
- **Trừ tồn kho theo UPDATE có điều kiện** — không bao giờ phát quá số suất đã khai báo.
- Kiểm định biên cho mọi tham số điểm/giá/tồn kho (chống tràn số và lỗi 500).
- Xác thực voucher yêu cầu mã dùng một lần ở cả bước xác nhận (không thể "đốt" voucher của khách
  chỉ bằng id).

### 6.2. Sổ cái điểm

Điểm được ghi theo kiểu **append-only ledger** (`point_transactions`) với các loại:
`earn` · `redeem` · `adjust` · `void` · `expire` · `bonus`. Số dư trên hồ sơ khách chỉ là cột đệm,
luôn được tính lại từ sổ cái — nên lịch sử của khách luôn giải thích được từng điểm.

### 6.3. Tác vụ nền (Sidekiq + cron)

| Lịch | Công việc |
|---|---|
| 03:00 hằng ngày | Hết hạn voucher · hết hạn điểm (FIFO) + nhắc trước 7 ngày · quà sinh nhật · win-back · tính lại điểm/hạng · dọn thông báo đã đọc cũ hơn 180 ngày · cập nhật trạng thái thuê bao |
| 03:30 hằng ngày | Tự động gia hạn / xuất hóa đơn |
| Mỗi 5 phút | Gửi broadcast đã hẹn giờ |
| Theo sự kiện | Gửi push · gửi OTP · tạo banner AI · duyệt ảnh nhiệm vụ bằng AI · trả thưởng thẻ tem đang chờ hàng |

### 6.4. Tích hợp ngoài

| Dịch vụ | Dùng cho |
|---|---|
| **Claude (Anthropic)** | Gợi ý nội dung chiến dịch · gợi ý bảng màu từ logo · nhận định khung giờ đông khách · kiểm tra ảnh chứng minh nhiệm vụ |
| **OpenAI Images** | Sinh ảnh banner chiến dịch |
| **PayOS** | Thanh toán gói dịch vụ (link/QR + webhook) |
| **Brevo / SMTP** | Gửi email OTP và email hệ thống |
| **Zalo ZNS** | Kênh OTP thay thế (cắm sẵn, bật khi có cấu hình) |
| **Web Push (VAPID)** | Thông báo đẩy cho PWA |
| **S3 / DigitalOcean Spaces** | Lưu ảnh (logo, banner, ảnh nhiệm vụ) có mirror xuống đĩa |

> Mọi tích hợp đều **fail-safe**: thiếu API key thì tính năng tự rơi về phương án không-AI /
> không-gửi, ứng dụng vẫn chạy bình thường.

### 6.5. Song ngữ

Toàn bộ ba ứng dụng có tiếng Việt và tiếng Anh, đổi ngôn ngữ ngay trên giao diện; mỗi workspace
có ngôn ngữ mặc định riêng, mỗi khách có ngôn ngữ riêng.

---

## 7. Phụ lục — Các luồng chính

**Tích điểm tại quầy**
```
Khách mở "Mã của tôi" (QR 120s)
  → Nhân viên quét ở tab Tích điểm
  → Nhập số tiền hóa đơn
  → Điểm = (tiền / tỷ lệ) × hệ số hạng
  → Ghi Purchase + bút toán sổ cái (có idempotency key)
  → Cộng tem / tiến độ nhiệm vụ / huy hiệu, hoàn tất referral nếu là đơn đầu
  → Điện thoại khách hiện "+X điểm", kiểm tra lên hạng
```

**Đổi và dùng ưu đãi**
```
Ví → chọn quà → Đổi điểm (khóa hàng, trừ điểm, trừ tồn kho) → Voucher vào ví
  → "Dùng ngay" sinh mã một lần + QR
  → Quầy quét ở tab Xác thực ưu đãi → voucher = used
  → Màn hình khách tự chuyển "đã dùng"
```

**Chiến dịch phát voucher**
```
Tạo chiến dịch → (AI viết nội dung, AI tạo banner có QR) → Bắt đầu chạy
  → In QR / chia sẻ link công khai → Khách quét → voucher vào ví + thông báo
  → Đẩy tới phân khúc khách → thông báo trong app + push
```

---

*Tài liệu mô tả tính năng — sinh từ mã nguồn thực tế của ứng dụng.*
