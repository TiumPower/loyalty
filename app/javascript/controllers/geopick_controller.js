import { Controller } from "@hotwired/stimulus"

// "Tự lấy toạ độ": resolve the address box into a latitude/longitude pair and
// drop it into the two fields, without saving. The merchant sees the place name
// that came back and decides whether to keep it.
//
// Nothing here writes to the branch — the form still has to be submitted — so a
// bad lookup costs a merchant nothing but a click.
export default class extends Controller {
  static targets = ["address", "lat", "lon", "button", "status", "source"]
  static values = { url: String, working: String, empty: String }

  async fetchCoords() {
    const address = this.addressTarget.value.trim()
    if (!address) { this.say(this.emptyValue, "warn"); this.addressTarget.focus(); return }

    this.busy(true)
    this.say(this.workingValue, "")
    try {
      const res = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
        },
        body: JSON.stringify({ address })
      })
      const data = await res.json()
      if (!data.ok) { this.say(data.error, "warn"); return }

      this.latTarget.value = data.lat
      this.lonTarget.value = data.lon
      // Tell the server this pair came from the lookup, not from the keyboard:
      // a hand-typed coordinate freezes the branch against future address
      // edits, and that is not what pressing this button asks for.
      if (this.hasSourceTarget) this.sourceTarget.value = "lookup"
      this.say(`${data.note} — ${data.label}`, "good")
    } catch (e) {
      this.say(this.element.dataset.geopickFailed || "…", "warn")
    } finally {
      this.busy(false)
    }
  }

  // Typing over the answer makes it the merchant's own again.
  typed() {
    if (this.hasSourceTarget) this.sourceTarget.value = "manual"
  }

  busy(on) {
    this.buttonTarget.disabled = on
    this.buttonTarget.classList.toggle("is-busy", on)
  }

  say(text, tone) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text || ""
    this.statusTarget.dataset.tone = tone || ""
    this.statusTarget.hidden = !text
  }
}
