import { Controller } from "@hotwired/stimulus"

// Pause / run a stamp card straight from the list. The checkbox it replaces was
// only applied when the whole card was saved, so a merchant who ticked it and
// walked away left the card running. This writes immediately over fetch and
// repaints the button + the "paused" chip in place — no page reload, so an open
// editor keeps whatever the merchant was typing.
export default class extends Controller {
  static targets = ["button", "chip"]
  static values = { url: String, active: Boolean, run: String, pause: String, working: String }

  async toggle(event) {
    // The button lives inside <summary>, whose default click opens/closes the
    // editor — not what someone pressing "Tạm dừng" asked for.
    event.preventDefault()
    event.stopPropagation()

    const btn = this.buttonTarget
    const previous = btn.textContent
    btn.disabled = true
    btn.textContent = this.workingValue

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const resp = await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" }
      })
      const data = await resp.json()
      if (!resp.ok || !data.ok) throw new Error("toggle failed")
      this.activeValue = data.active
      this.render()
    } catch (e) {
      btn.textContent = previous
      alert("Không đổi được trạng thái thẻ tem. Vui lòng thử lại.")
    } finally {
      btn.disabled = false
    }
  }

  // Paint from activeValue so the button always states the CURRENT state and
  // the action it offers cannot drift apart.
  render() {
    const on = this.activeValue
    this.buttonTarget.textContent = on ? this.pauseValue : this.runValue
    this.buttonTarget.classList.toggle("l-btn-soft", on)
    this.buttonTarget.classList.toggle("l-btn-primary", !on)
    if (this.hasChipTarget) this.chipTarget.hidden = on
  }
}
