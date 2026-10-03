import { Controller } from "@hotwired/stimulus"

// Xem ảnh đánh giá ở cỡ đầy đủ, ngay trong app.
//
// Trước đây ảnh mở bằng `target="_blank"`: trong một PWA đã cài, cái đó bật ra
// trình duyệt ngoài — khách rơi khỏi app và phải tự tìm đường quay lại. Giờ ảnh
// mở trong một <dialog> có nút đóng, bấm nền hoặc Esc cũng đóng.
export default class extends Controller {
  static targets = ["dialog", "image"]

  open(event) {
    event.preventDefault()
    const trigger = event.currentTarget
    this.imageTarget.src = trigger.dataset.lightboxSrc || trigger.href
    this.imageTarget.alt = trigger.dataset.lightboxAlt || ""
    this.dialogTarget.showModal()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.cleared()
  }

  // Bấm ra nền (chính thẻ <dialog>, không phải ảnh bên trong) thì đóng.
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // Bắt cả sự kiện `close` của chính <dialog>, không chỉ nút ✕: nhấn Esc thì
  // dialog tự đóng mà không đi qua Stimulus. Bỏ `src` để một danh sách dài
  // không giữ lại mọi ảnh cỡ đầy đủ trong bộ nhớ.
  cleared() {
    this.imageTarget.removeAttribute("src")
  }
}
