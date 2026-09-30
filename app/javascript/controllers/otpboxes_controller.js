import { Controller } from "@hotwired/stimulus"

// Paints a six-digit code into decorative boxes while the real input — which
// sits invisibly on top — keeps the keyboard, paste and autofill working.
export default class extends Controller {
  static targets = ["input", "boxes"]

  connect() { this.paint() }

  paint() {
    const digits = (this.inputTarget.value || "").replace(/\D/g, "").slice(0, 6)
    this.inputTarget.value = digits
    this.boxesTarget.querySelectorAll("span").forEach((box, i) => {
      box.textContent = digits[i] || ""
      box.classList.toggle("on", i === digits.length || (i < digits.length))
    })
  }
}
