import { Controller } from "@hotwired/stimulus"

// Dẫn thẳng tới một khối nằm giữa trang dài.
//
// Mục "Quyền riêng tư & dữ liệu" mở trang sửa hồ sơ, nhưng câu trả lời cho mục
// đó chỉ là một dòng ở gần cuối biểu mẫu — khách bấm vào rồi rơi vào đầu trang
// họ không hỏi, và không biết mình được đưa tới đâu. Khi địa chỉ có #id của
// khối này thì cuộn tới đúng nó và loé lên một nhịp để mắt bắt được.
//
// Không dùng `:target` của CSS: Turbo đổi địa chỉ bằng pushState, mà `:target`
// không phải lúc nào cũng tính lại sau pushState.
export default class extends Controller {
  connect() {
    if (!this.element.id || window.location.hash !== `#${this.element.id}`) return

    // Đợi hết khung hình hiện tại: Turbo vừa thay xong thân trang, đo vị trí
    // ngay lúc này là đo trên bố cục cũ.
    requestAnimationFrame(() => {
      const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
      this.element.scrollIntoView({ behavior: still ? "auto" : "smooth", block: "center" })
      this.element.classList.add("is-spot")
      this.timer = setTimeout(() => this.element.classList.remove("is-spot"), 2200)
    })
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
