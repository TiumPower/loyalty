import { Controller } from "@hotwired/stimulus"

// A tab strip that drives a Turbo Frame. Only the frame's contents are swapped,
// so the strip itself is never re-rendered and the tab you just clicked kept the
// old styling — the highlight stayed on the previous tab while a different tool
// was on screen. Move `active` on click so the strip matches what is showing.
export default class extends Controller {
  pick(event) {
    this.element.querySelectorAll("a").forEach((a) => a.classList.remove("active"))
    event.currentTarget.classList.add("active")
  }
}
