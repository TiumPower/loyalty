# Tự động deploy

`deploy.yml` chạy `cap production deploy` ngay sau khi workflow **CI** kết thúc
trên nhánh `main` — **kể cả khi CI đỏ**. Đó là lựa chọn có chủ ý; phần "Vì sao"
ở cuối trang nói rõ đánh đổi.

`rollback.yml` chạy `cap production deploy:rollback` khi bấm tay, để có đường
lùi nhanh khi một bản đỏ làm hỏng production.

## Máy chủ lấy mã từ đâu

Khi deploy tay, máy chủ `103.116.38.152` mượn SSH agent của máy đang deploy
(`forward_agent: true` trong `config/deploy/production.rb`) để kéo mã từ
GitHub — nó không có khoá GitHub nào của riêng mình.

GitHub Actions không mượn được như vậy, và **tổ chức TiumPower tắt Deploy
keys** nên cũng không thể cấp cho máy chủ một khoá riêng. Thay vào đó, workflow
truyền `REPO_URL` dạng HTTPS kèm `GITHUB_TOKEN` — token GitHub tự cấp cho mỗi
lần chạy và **tự hết hạn khi lần chạy kết thúc**:

```
https://x-access-token:<token>@github.com/TiumPower/loyalty.git
```

`config/deploy.rb` đọc `REPO_URL` nếu có, không thì dùng URL SSH như cũ — nên
deploy tay không đổi gì.

Capistrano ghi URL đó vào config của git mirror trên máy chủ, nên sau mỗi lần
deploy (kể cả khi hỏng) workflow gọi `cap production deploy:scrub_repo_url` để
trả về URL SSH. Token đã chết rồi, nhưng không để bí mật nằm lại trên đĩa.

Hệ quả: **không cần tạo Deploy key, không cần GitHub App, không có bí mật dài
hạn nào phải xoay vòng.** Chỉ còn đúng một khoá SSH để mở máy chủ.

## Cần chuẩn bị đúng hai thứ

### 1. Tạo khoá SSH riêng cho CI

Đừng dùng khoá cá nhân đang có trên máy. Tạo khoá mới để lúc cần thu hồi thì
chỉ thu hồi quyền của CI:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy-loyalty" -f ~/.ssh/loyalty_ci -N ""
ssh-copy-id -i ~/.ssh/loyalty_ci.pub deploy@103.116.38.152
```

### 2. Hai secret trong GitHub repo → Settings → Secrets and variables → Actions

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

Đây là yêu cầu của chủ sản phẩm. Tình trạng CI lúc viết tài liệu này
(2026-10-01):

| Job | Tình trạng |
|---|---|
| `test` | **xanh** — 442 runs, 0 failures |
| `scan_ruby` (brakeman) | **xanh** — no warnings |
| `scan_js` (importmap audit) | xanh |
| `lint` (rubocop) | **ĐỎ** — 812 lỗi style, đỏ ở **mọi** lần push |

Tức là CI đỏ vì đúng **một** job, và job đó đỏ vì style chứ không vì mã sai.
"Chỉ deploy khi CI xanh" sẽ chặn mọi bản deploy cho tới khi dọn xong rubocop.
Deploy-bất-chấp làm pipeline chạy được **ngay**.

Cái giá có thật: từ giờ một commit làm **hỏng test** cũng ra tới khách hàng,
y như một commit chỉ sai khoảng trắng. Hai thứ bù lại:

1. **Capistrano đổi release bằng symlink.** Một deploy *hỏng giữa chừng*
   (asset không build được, migration lỗi) để nguyên bản cũ đang chạy —
   production không sập. Rủi ro thật là deploy *thành công* với mã sai.
2. **Workflow Rollback** quay về release trước trong vài giây.

Vì chỉ còn `lint` đỏ, đường về một CI đáng để chặn deploy khá ngắn:

1. `bin/rubocop -A` tự sửa 433 lỗi, rồi `bin/rubocop --auto-gen-config` để
   gạt phần còn lại sang `.rubocop_todo.yml` — hoặc bỏ hẳn job `lint` khỏi
   `ci.yml` nếu không định dùng.
2. Rồi thêm `github.event.workflow_run.conclusion == 'success'` vào điều kiện
   `if` trong `deploy.yml` — đúng một dòng.

(`test:system` chạy trong CI trong khi `test/system/` chưa có file nào, nhưng
0 test thì thoát mã 0 — không làm CI đỏ, chỉ tốn vài giây cài Chrome.)
