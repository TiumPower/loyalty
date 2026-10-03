import { Controller } from "@hotwired/stimulus"

// Khung "Khách sẽ thấy" đổi theo từng phím gõ.
//
// Trước đây nó chỉ vẽ theo dữ liệu ĐÃ LƯU, nên gõ tên xong vẫn thấy "(chưa đặt
// tên)" — phải lưu rồi mới biết thẻ trông ra sao, mà lưu rồi thì khách đã thấy.
// Mọi thứ hiện trong khung đó giờ cập nhật ngay: tên, mô tả, điểm đổi, và emoji
// khi chưa có ảnh.
export default class extends Controller {
  static targets = ["title", "desc", "points", "icon", "titleOut", "descOut", "pointsOut", "art"]
  static values = { untitled: String, pointsLabel: String }

  connect() {
    this.render()
  }

  render() {
    this.renderTitle()
    this.renderDesc()
    this.renderPoints()
    this.renderIcon()
  }

  renderTitle() {
    if (!this.hasTitleTarget || !this.hasTitleOutTarget) return
    const value = this.titleTarget.value.trim()
    this.titleOutTarget.textContent = value || this.untitledValue
  }

  renderDesc() {
    if (!this.hasDescTarget || !this.hasDescOutTarget) return
    const value = this.descTarget.value.trim()
    // Cắt đúng chỗ máy chủ cắt, để bản xem trước không hứa một dòng dài hơn
    // dòng khách sẽ thấy thật.
    this.descOutTarget.textContent = value.length > 90 ? `${value.slice(0, 90)}...` : value
    this.descOutTarget.hidden = value.length === 0
  }

  renderPoints() {
    if (!this.hasPointsTarget || !this.hasPointsOutTarget) return
    const n = parseInt(this.pointsTarget.value, 10)
    const ok = Number.isFinite(n) && n > 0
    this.pointsOutTarget.hidden = !ok
    if (ok) this.pointsOutTarget.textContent = this.pointsLabelValue.replace("%{n}", n.toLocaleString("vi-VN"))
  }

  // Emoji chỉ hiện khi CHƯA có ảnh — có ảnh rồi thì ảnh đã chiếm chỗ đó.
  renderIcon() {
    if (!this.hasIconTarget || !this.hasArtTarget) return
    const em = this.artTarget.querySelector(".l-artfallback .em")
    if (em) em.textContent = this.iconTarget.value.trim() || "🎁"
  }
}
