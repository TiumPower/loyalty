import { Controller } from "@hotwired/stimulus"

// Chip-style multi-select backed by real checkboxes, so the form posts without
// any JS and the chips only supply the visual state.
export default class extends Controller {
  static targets = ["tag"]

  // Radio group: only one chip stays lit.
  pick(e) {
    const scope = e.currentTarget.closest("[data-controller~='tagpick']") || this.element
    scope.querySelectorAll("[data-tagpick-target='tag']").forEach((t) => t.classList.remove("on"))
    e.currentTarget.closest("[data-tagpick-target='tag']")?.classList.add("on")
  }

  toggle(e) {
    e.currentTarget.closest("[data-tagpick-target='tag']")
      ?.classList.toggle("on", e.currentTarget.checked)
  }
}
