import { Controller } from "@hotwired/stimulus"

// Tabs that show one group of a list at a time.
//
// These used to be anchors that jumped to a heading, with a scrollspy lighting
// whichever group you had scrolled to. On a short card — a shop with two
// missions — the whole page scrolls barely a hundred pixels, so tapping "This
// week" moved almost nothing and the tab read as broken. Filtering is
// unambiguous at any page length.
export default class extends Controller {
  static targets = ["tab", "group"]

  connect() { this.show(this.tabTargets[0]?.dataset.group || "all") }

  pick(event) { this.show(event.currentTarget.dataset.group) }

  show(key) {
    this.current = key
    this.tabTargets.forEach((t) => t.classList.toggle("active", t.dataset.group === key))
    this.groupTargets.forEach((g) => {
      g.hidden = key !== "all" && g.dataset.group !== key
    })
  }
}
