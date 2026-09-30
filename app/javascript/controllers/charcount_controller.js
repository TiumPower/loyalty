import { Controller } from "@hotwired/stimulus"

// Live "0/500" beside a textarea's label, so the limit is visible while typing
// rather than discovered when the field stops accepting characters.
export default class extends Controller {
  static targets = ["input", "out"]

  connect() { this.count() }

  count() {
    const max = this.inputTarget.maxLength
    const n = this.inputTarget.value.length
    this.outTarget.textContent = max > 0 ? `${n}/${max}` : `${n}`
    this.outTarget.style.color = max > 0 && n >= max ? "var(--warn)" : ""
  }
}
