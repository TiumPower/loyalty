import { Controller } from "@hotwired/stimulus"

// Nút back phải quay về trang TRƯỚC ĐÓ, không phải về một trang cố định. Vào
// trang cá nhân rồi vào thông báo, bấm back mà ra thẳng màn hình chính thì
// khách mất chỗ mình đang đứng; href trên nút chỉ là nơi màn đó "thường" đến
// từ, không phải nơi khách vừa rời đi.
//
// Nhưng `history.length > 1` một mình thì chưa đủ: mở link cửa hàng từ Zalo
// rồi bấm back là rơi ngược ra Zalo, tức là khách rớt khỏi app. Nên chỉ lùi
// khi biết trong tab này đã có ít nhất một lượt chuyển trang của chính app —
// lúc đó trang trước chắc chắn là trang của mình. Chưa chắc thì đi theo href:
// đường lui luôn đúng, chỉ kém tinh ý một chút.
const KEY = "pwaNavigated"

let loads = 0
document.addEventListener("turbo:load", () => {
  loads += 1
  // Lượt đầu là trang khách vừa mở từ bên ngoài; từ lượt thứ hai trở đi mới là
  // app tự đi. Cờ đã bật thì không tắt — tải lại trang không xoá sự thật là
  // trước đó đã đi trong app.
  if (loads > 1) {
    try { sessionStorage.setItem(KEY, "1") } catch (_) {}
  }
})

export default class extends Controller {
  back(e) {
    if (!this.canGoBack) return
    e.preventDefault()
    window.history.back()
  }

  get canGoBack() {
    if (window.history.length <= 1) return false
    // Cửa sổ ẩn danh hoặc trình duyệt chặn lưu trữ thì ném lỗi, không phải
    // trả rỗng.
    try { return sessionStorage.getItem(KEY) === "1" } catch (_) { return false }
  }
}
