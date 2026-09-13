import { Controller } from "@hotwired/stimulus"

// Interactive 1–5 star picker backing a hidden input.
export default class extends Controller {
  static targets = ["star", "input", "submit", "hint"]

  connect() { this.paint(parseInt(this.inputTarget.value, 10) || 0) }

  set(e) {
    const v = parseInt(e.currentTarget.dataset.value, 10)
    this.inputTarget.value = v
    this.paint(v)
  }

  // A review with no stars chosen cannot be submitted — see the controller:
  // defaulting to 5 was inflating every shop's public average.
  gate(v) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = v < 1
    if (this.hasHintTarget) this.hintTarget.hidden = v >= 1
  }

  paint(v) {
    this.starTargets.forEach((s, i) => {
      s.textContent = i < v ? "★" : "☆"
      s.style.opacity = i < v ? "1" : ".45"
    })
    this.gate(v)
  }
}
