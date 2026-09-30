import { Controller } from "@hotwired/stimulus"

// Bottom sheet held in the page and revealed on demand — the design confirms a
// redemption over the reward it is about, not in a separate dialog.
export default class extends Controller {
  static targets = ["panel"]

  open() {
    this.panelTarget.hidden = false
    document.body.style.overflow = "hidden"
    this._esc = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this._esc)
  }

  close() {
    this.panelTarget.hidden = true
    document.body.style.overflow = ""
    if (this._esc) document.removeEventListener("keydown", this._esc)
  }
}
