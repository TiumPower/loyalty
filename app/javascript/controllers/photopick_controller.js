import { Controller } from "@hotwired/stimulus"

// "Add visit photos" on the review form. Shows what was picked before the
// review is sent — a file input on its own says only "3 files", which is no
// help when you are choosing which photos of a coffee to post.
export default class extends Controller {
  static targets = ["input", "grid", "count", "empty"]
  static values = { max: Number, tooMany: String }

  connect() { this.render() }

  pick() { this.inputTarget.click() }

  changed() {
    const files = Array.from(this.inputTarget.files || [])
    if (files.length > this.maxValue) {
      alert(this.tooManyValue)
      this.inputTarget.value = ""
    }
    this.render()
  }

  clear() {
    this.inputTarget.value = ""
    this.render()
  }

  render() {
    const files = Array.from(this.inputTarget.files || [])
    this.revoke()
    this.urls = files.map((f) => URL.createObjectURL(f))
    this.gridTarget.innerHTML = this.urls
      .map((u) => `<span class="l-photo"><img src="${u}" alt=""></span>`)
      .join("")
    this.gridTarget.hidden = files.length === 0
    if (this.hasEmptyTarget) this.hasEmptyTarget && (this.emptyTarget.hidden = files.length > 0)
    if (this.hasCountTarget) this.countTarget.textContent = files.length ? `${files.length}/${this.maxValue}` : ""
  }

  // Object URLs hold the file in memory until they are released.
  revoke() { (this.urls || []).forEach((u) => URL.revokeObjectURL(u)) }
  disconnect() { this.revoke() }
}
