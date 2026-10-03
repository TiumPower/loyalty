import { Controller } from "@hotwired/stimulus"

// Chọn ảnh phần thưởng: bấm hoặc KÉO THẢ, và xem trước ngay ở khung "Khách sẽ
// thấy" bên cạnh.
//
// Trước đây đây là một <input type="file"> trần: nút ghi "Choose File" bằng
// tiếng Anh do trình duyệt vẽ (không sửa được bằng CSS hay nhãn), không kéo thả
// được, và ảnh vừa chọn chỉ hiện sau khi lưu — tức phải lưu rồi mới biết nó cắt
// ra trông thế nào.
export default class extends Controller {
  static targets = ["input", "zone", "thumb", "art", "name", "error", "remove", "clear"]
  static values = {
    maxBytes: { type: Number, default: 5 * 1024 * 1024 },
    types: { type: String, default: "image/png,image/jpeg,image/webp" },
    tooBig: String,
    badType: String,
    placeholder: String
  }

  connect() {
    this.urls = []
    // Giữ lại khung xem trước ban đầu để còn hoàn nguyên khi bỏ ảnh.
    this.originalThumb = this.hasThumbTarget ? this.thumbTarget.innerHTML : ""
    this.originalArt = this.hasArtTarget ? this.artTarget.innerHTML : ""
  }

  disconnect() {
    this.urls.forEach((u) => URL.revokeObjectURL(u))
  }

  // Bấm vào vùng thả cũng mở hộp chọn tệp — vùng thả là nút bấm, không chỉ là
  // đích để thả.
  browse(event) {
    if (event.target.closest("button, a, label")) return
    this.inputTarget.click()
  }

  over(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("is-over")
  }

  leave() {
    this.zoneTarget.classList.remove("is-over")
  }

  drop(event) {
    event.preventDefault()
    this.leave()
    const file = event.dataTransfer?.files?.[0]
    if (!file) return
    // Gán vào chính input để form vẫn gửi tệp đi như bình thường — không có
    // đường nào khác đưa tệp thả được vào một multipart form.
    const dt = new DataTransfer()
    dt.items.add(file)
    this.inputTarget.files = dt.files
    this.show(file)
  }

  change() {
    const file = this.inputTarget.files?.[0]
    if (file) this.show(file)
  }

  show(file) {
    const problem = this.problemWith(file)
    if (problem) {
      this.fail(problem)
      this.inputTarget.value = ""
      return
    }
    this.clearError()

    const url = URL.createObjectURL(file)
    this.urls.push(url)
    const img = `<img src="${url}" style="width:100%;height:100%;object-fit:cover;display:block;">`
    if (this.hasThumbTarget) this.thumbTarget.innerHTML = img
    if (this.hasArtTarget) this.artTarget.innerHTML = img
    if (this.hasNameTarget) this.nameTarget.textContent = file.name
    // Chọn ảnh mới thì rõ ràng là không còn muốn xoá ảnh cũ nữa.
    if (this.hasRemoveTarget) this.removeTarget.checked = false
    if (this.hasClearTarget) this.clearTarget.hidden = false
  }

  // Bỏ ảnh vừa chọn, trả khung xem trước về như lúc mở trang.
  clear(event) {
    event.preventDefault()
    this.inputTarget.value = ""
    if (this.hasThumbTarget) this.thumbTarget.innerHTML = this.originalThumb
    if (this.hasArtTarget) this.artTarget.innerHTML = this.originalArt
    if (this.hasNameTarget) this.nameTarget.textContent = this.placeholderValue
    if (this.hasClearTarget) this.clearTarget.hidden = true
    this.clearError()
  }

  problemWith(file) {
    const allowed = this.typesValue.split(",")
    if (!allowed.includes(file.type)) return this.badTypeValue
    if (file.size > this.maxBytesValue) return this.tooBigValue
    return null
  }

  fail(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}
