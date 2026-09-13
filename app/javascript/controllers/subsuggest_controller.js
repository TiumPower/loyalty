import { Controller } from "@hotwired/stimulus"

// Fills the subdomain field from the "this one is free" suggestion shown when
// the chosen address was taken, so the form can be finished in one tap.
export default class extends Controller {
  static targets = ["field", "reveal", "password"]

  apply(e) {
    const value = e.currentTarget.dataset.sub
    if (!value || !this.hasFieldTarget) return
    this.fieldTarget.value = value
    this.fieldTarget.focus()
    this.fieldTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Typing a brand-new password blind on a phone is how people end up locked
  // out of the account they just created.
  toggle() {
    if (!this.hasPasswordTarget) return
    const showing = this.passwordTarget.type === "text"
    this.passwordTarget.type = showing ? "password" : "text"
    if (this.hasRevealTarget) this.revealTarget.textContent = showing ? "👁" : "🙈"
  }
}
