# Tự động deploy

`deploy.yml` chạy `cap production deploy` ngay sau khi workflow **CI** kết thúc
trên nhánh `main` — **kể cả khi CI đỏ**. Đó là lựa chọn có chủ ý; phần "Vì sao"
ở cuối trang nói rõ đánh đổi.

`rollback.yml` chạy `cap production deploy:rollback` khi bấm tay, để có đường
lùi nhanh khi một bản đỏ làm hỏng production.

## Cần chuẩn bị đúng ba thứ

Máy chủ `103.116.38.152` **không có khoá GitHub riêng** — nó mượn SSH agent của
máy đang deploy (`forward_agent: true` trong `config/deploy/production.rb`).
Nên một khoá duy nhất phải làm được cả hai việc: mở SSH vào máy chủ, và kéo mã
từ GitHub.

### 1. Tạo khoá riêng cho CI

Đừng dùng khoá cá nhân đang có trên máy. Tạo khoá mới để lúc cần thu hồi thì
chỉ thu hồi quyền của CI:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy-loyalty" -f ~/.ssh/loyalty_ci -N ""
```

### 2. Cho khoá đó vào ba nơi

**a. Máy chủ** — để GitHub Actions SSH vào được:

```bash
ssh-copy-id -i ~/.ssh/loyalty_ci.pub deploy@103.116.38.152
```

**b. GitHub repo → Settings → Deploy keys → Add deploy key** — để máy chủ kéo
được mã. Dán nội dung `~/.ssh/loyalty_ci.pub`, đặt tên `github-actions`,
**KHÔNG tích** "Allow write access".

```bash
cat ~/.ssh/loyalty_ci.pub
```

**c. GitHub repo → Settings → Secrets and variables → Actions** — hai secret:

| Tên secret | Lấy từ đâu |
|---|---|
| `DEPLOY_SSH_KEY` | `cat ~/.ssh/loyalty_ci` — **toàn bộ** khoá riêng, kể cả hai dòng `-----BEGIN/END-----` |
| `DEPLOY_KNOWN_HOSTS` | `ssh-keyscan -t ed25519,rsa 103.116.38.152` (bỏ các dòng bắt đầu bằng `#`) |

`DEPLOY_KNOWN_HOSTS` để ghim khoá máy chủ. Mỗi lần chạy là một runner mới
tinh, nên nếu tắt kiểm tra bằng `StrictHostKeyChecking=no` thì coi như không
xác thực máy chủ lần nào cả.

### 3. Thử

Vào tab **Actions → Deploy → Run workflow**. Chạy tay trước một lần; chạy được
thì lần push tiếp theo lên `main` sẽ tự deploy sau khi CI xong.

## Những gì workflow cố tình KHÔNG làm

- **Không deploy khi CI bị huỷ (`cancelled`).** Huỷ gần như luôn là do có
  commit mới đè lên, và CI của commit mới sẽ tự deploy. Đỏ thì vẫn deploy —
  chỉ "huỷ" mới bỏ qua.
- **Không deploy từ pull request.** Chỉ nhận CI của `push` lên `main`.
- **Không chạy hai deploy cùng lúc.** `concurrency: deploy-production` xếp
  hàng, và không huỷ lần đang chạy giữa chừng — cắt ngang một `cap deploy` để
  lại thư mục release dở dang trên máy chủ.
- **Không deploy đúng commit mà CI đã chạy**, mà deploy `main` tại thời điểm
  đó. Hai cách đều có lý; cách này giống hệt `cap production deploy` chạy tay
  và không thêm chỗ nào để hỏng. Commit mà CI chạy vẫn được ghi trong job
  summary.

## Vì sao vẫn deploy khi CI đỏ — và cái giá

Đây là yêu cầu của chủ sản phẩm, và nó là đánh đổi hợp lý khi **CI đang đỏ vì
lý do không liên quan đến chất lượng mã**. Thời điểm viết tài liệu này:

- `bin/rubocop` báo **812 lỗi style** → job `lint` đỏ ở **mọi** lần push.
- `bin/rails test:system` chạy trong CI nhưng `test/system/` **không có file
  nào**.
- `test/integration/landing_page_test.rb` có một lỗi đã biết (robots.txt đang
  cố tình chặn vì sản phẩm chưa mở công khai).

Nghĩa là CI gần như không bao giờ xanh, nên "chỉ deploy khi CI xanh" sẽ chặn
mọi bản deploy. Deploy-bất-chấp là cách làm cho pipeline chạy được **ngay**.

Cái giá: một commit làm hỏng test thật vẫn ra tới khách hàng. Hai thứ bù lại:

1. **Capistrano đổi release bằng symlink.** Một deploy *hỏng giữa chừng*
   (asset không build được, migration lỗi) để nguyên bản cũ đang chạy —
   production không sập. Rủi ro thật là deploy *thành công* với mã sai.
2. **Workflow Rollback** quay về release trước trong vài giây.

Khi nào muốn CI có ý nghĩa trở lại, làm theo thứ tự này:

1. `bin/rubocop -A` để tự sửa 433 lỗi sửa được, rồi chỉnh `.rubocop.yml` cho
   phần còn lại — hoặc bỏ job `lint` khỏi `ci.yml` nếu không dùng tới.
2. Bỏ `test:system` khỏi lệnh test trong `ci.yml` cho tới khi thật sự có
   system test.
3. Xử lý nốt lỗi `landing_page_test`.
4. Rồi thêm `github.event.workflow_run.conclusion == 'success'` vào điều kiện
   `if` trong `deploy.yml` — đúng một dòng.
