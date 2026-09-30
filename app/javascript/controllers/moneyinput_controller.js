import { Controller } from "@hotwired/stimulus"

// Groups the digits of a money field as it is typed: 5000000 → 5.000.000.
//
// A cashier reading back "5000000" has to count zeros to know whether the bill
// was five hundred thousand or five million, and at the counter that is exactly
// the moment there is no time to. The separator follows the app's locale, so it
// matches every other amount on screen.
//
// The visible field carries no name; a hidden one posts plain digits, so the
// server never has to unpick the formatting.
export default class extends Controller {
  static targets = ["visible", "raw"]
  static values = { locale: { type: String, default: "vi-VN" } }

  connect() { this.format() }

  format() {
    const el = this.visibleTarget
    const digits = el.value.replace(/\D/g, "").slice(0, 12)
    // Where the caret sits, counted in digits rather than characters, so
    // inserting a separator does not push it around.
    const digitsBeforeCaret = el.value.slice(0, el.selectionStart ?? el.value.length).replace(/\D/g, "").length

    const formatted = digits ? Number(digits).toLocaleString(this.localeValue) : ""
    el.value = formatted
    if (this.hasRawTarget) this.rawTarget.value = digits

    if (document.activeElement === el) {
      let seen = 0, pos = formatted.length
      for (let i = 0; i < formatted.length; i++) {
        if (/\d/.test(formatted[i])) seen++
        if (seen === digitsBeforeCaret) { pos = i + 1; break }
      }
      if (digitsBeforeCaret === 0) pos = 0
      el.setSelectionRange(pos, pos)
    }
  }
}
