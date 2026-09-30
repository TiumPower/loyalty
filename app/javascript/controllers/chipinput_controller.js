import { Controller } from "@hotwired/stimulus"

// Type a name, press Enter, it becomes a removable chip.
//
// This replaced a textarea whose hint read "separate with commas" — a rule the
// merchant had to remember and the screen never showed them keeping. Each item
// is now visibly its own thing, and the count against the limit is on screen.
export default class extends Controller {
  static targets = ["list", "input", "count", "hint"]
  static values = { name: String, max: Number, maxLength: Number, full: String, duplicate: String }

  connect() {
    this.items = Array.from(this.listTarget.querySelectorAll("[data-value]")).map((e) => e.dataset.value)
    this.render()
    // A merchant who types a name and goes straight for Save would otherwise
    // lose it: commit whatever is in the box when the form is sent.
    this.form = this.element.closest("form")
    this.onSubmit = () => this.commit()
    this.form?.addEventListener("submit", this.onSubmit)
  }

  disconnect() { this.form?.removeEventListener("submit", this.onSubmit) }

  keydown(event) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      this.commit()
    } else if (event.key === "Backspace" && this.inputTarget.value === "" && this.items.length) {
      this.items.pop()
      this.render()
    }
  }

  // Pasting a list from a menu or a spreadsheet should still work.
  paste(event) {
    const text = event.clipboardData?.getData("text") || ""
    if (!text.includes(",") && !text.includes("\n")) return
    event.preventDefault()
    text.split(/[,\n]/).forEach((part) => this.add(part))
    this.render()
  }

  blur() { this.commit() }

  commit() {
    if (this.add(this.inputTarget.value)) this.inputTarget.value = ""
    this.render()
  }

  remove(event) {
    this.items.splice(Number(event.currentTarget.dataset.index), 1)
    this.render()
    this.inputTarget.focus()
  }

  add(raw) {
    const value = raw.trim().slice(0, this.maxLengthValue)
    if (!value) return false
    if (this.items.length >= this.maxValue) return this.say(this.fullValue)
    if (this.items.some((i) => i.toLowerCase() === value.toLowerCase())) return this.say(this.duplicateValue)
    this.items.push(value)
    this.say("")
    return true
  }

  say(message) {
    if (this.hasHintTarget) this.hintTarget.textContent = message
    return false
  }

  render() {
    this.listTarget.innerHTML = this.items
      .map((v, i) => `
        <span class="l-chipedit" data-value="${this.escape(v)}">
          <span>${this.escape(v)}</span>
          <button type="button" data-index="${i}" data-action="chipinput#remove" aria-label="×">✕</button>
          <input type="hidden" name="${this.nameValue}" value="${this.escape(v)}">
        </span>`)
      .join("")
    const full = this.items.length >= this.maxValue
    this.inputTarget.disabled = full
    this.inputTarget.placeholder = full ? this.fullValue : this.inputTarget.dataset.placeholder
    if (this.hasCountTarget) this.countTarget.textContent = `${this.items.length}/${this.maxValue}`
  }

  escape(text) {
    return String(text).replace(/[&<>"']/g, (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }
}
