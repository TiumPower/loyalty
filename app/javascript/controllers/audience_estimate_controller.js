import { Controller } from "@hotwired/stimulus"

// Keeps "this will reach N customers" honest while the audience select changes.
// The counts are resolved server-side once (one query per segment) and handed
// over as JSON, so switching audiences costs nothing.
export default class extends Controller {
  static targets = ["select", "value", "data"]

  connect() {
    try { this.counts = JSON.parse(this.dataTarget.dataset.counts || "{}") } catch { this.counts = {} }
    this.update()
  }

  update() {
    if (!this.hasSelectTarget || !this.hasValueTarget) return
    const n = this.counts[this.selectTarget.value]
    this.valueTarget.textContent = n == null ? "—" : n.toLocaleString("vi-VN")
  }
}
