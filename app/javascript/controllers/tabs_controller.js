import { Controller } from "@hotwired/stimulus"

// Generic tab group. Supports two markup conventions:
//   • data-tab="…"  + data-tabs-key-value / data-tabs-default-value  (merchant)
//   • data-name="…" + data-tabs-active-value                         (customer)
// The active tab is remembered in localStorage (keyed by data-tabs-key-value) so a
// refresh — or a form POST that redirects back — stays put; an explicit
// data-tabs-active-value (server-driven, e.g. ?tab=rewards) always wins on load.
// The CSS class marking the active tab is configurable (default "l-chip-brand");
// the customer segmented control (.l-wtabs) passes "active".
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    key: String,
    default: String,
    active: String,
    activeClass: { type: String, default: "l-chip-brand" }
  }

  connect() {
    const initial = this.activeValue || this.load() || this.defaultValue || this.nameOf(this.tabTargets[0])
    if (initial) this.activate(initial)
  }

  select(e) { this.activate(this.nameOf(e.currentTarget)) }

  // A tab/panel's identity, from either convention.
  nameOf(el) { return el ? (el.dataset.tab || el.dataset.name) : undefined }

  activate(name) {
    let matched = false
    this.tabTargets.forEach((t) => {
      const on = this.nameOf(t) === name
      matched = matched || on
      t.classList.toggle(this.activeClassValue, on)
      t.setAttribute("aria-selected", on)
    })
    if (!matched) name = this.nameOf(this.tabTargets[0])
    this.panelTargets.forEach((p) => { p.hidden = this.nameOf(p) !== name })
    this.save(name)
  }

  save(n) { try { localStorage.setItem(this.storageKey, n) } catch (e) {} }
  load()  { try { return localStorage.getItem(this.storageKey) } catch (e) { return null } }
  get storageKey() { return `tabs:${this.keyValue || this.element.id || "default"}` }
}
