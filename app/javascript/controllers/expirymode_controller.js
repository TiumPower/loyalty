import { Controller } from "@hotwired/stimulus"

// Voucher validity mode: enable only the input for the chosen option (N days
// after claim vs a fixed expiry date). Disabled inputs aren't submitted, so the
// controller reads exactly one, unambiguously.
export default class extends Controller {
  static targets = ["radio", "relativeInput", "fixedInput", "relativeRow", "fixedRow"]

  connect() { this.apply() }
  switch() { this.apply() }

  apply() {
    const mode = this.radioTargets.find((r) => r.checked)?.value || "relative"
    if (this.hasRelativeInputTarget) this.relativeInputTarget.disabled = mode !== "relative"
    if (this.hasFixedInputTarget) this.fixedInputTarget.disabled = mode !== "fixed"
    if (this.hasRelativeRowTarget) this.dim(this.relativeRowTarget, mode !== "relative")
    if (this.hasFixedRowTarget) this.dim(this.fixedRowTarget, mode !== "fixed")
  }

  // Làm nhạt dòng KHÔNG được chọn, nhưng không làm nhạt nút radio của nó (radio
  // mờ đọc như đã bị khoá). Phần nhìn nằm hết ở CSS `.l-optrow.off` — kể cả
  // trạng thái rê chuột, thứ mà style nội tuyến không tả được: dòng đang mờ khi
  // rê chuột phải sáng lên để nói rằng bấm vào là chọn được nó.
  dim(row, off) {
    if (row) row.classList.toggle("off", off)
  }
}
