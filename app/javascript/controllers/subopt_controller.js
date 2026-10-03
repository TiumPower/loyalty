import { Controller } from "@hotwired/stimulus"

// Tuỳ chọn con chỉ hiện khi công tắc cha đang bật.
//
// "Ghép mã QR vào banner" chỉ có nghĩa khi "Tạo banner bằng AI" đang bật, nhưng
// trước đây nó luôn hiện và nằm chen giữa mục AI với mục tải ảnh lên — hai cách
// làm banner thay thế cho nhau mà bị đẩy xa nhau, còn một tuỳ chọn không dùng
// được thì vẫn chiếm chỗ.
export default class extends Controller {
  static targets = ["switch", "child"]

  connect() { this.apply() }

  apply() {
    const on = this.hasSwitchTarget && this.switchTarget.checked
    this.childTargets.forEach((el) => { el.hidden = !on })
  }
}
