import { Controller } from "@hotwired/stimulus"

// Highlights whichever section of the page you are actually looking at.
//
// The mission tabs jump to a group rather than filtering, so no tab was ever
// marked current and both of them looked the same — you could not tell which
// one you were on. Now the highlight follows the scroll position.
export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.sections = this.linkTargets
      .map((a) => ({ link: a, el: document.querySelector(a.getAttribute("href")) }))
      .filter((s) => s.el)
    if (!this.sections.length) return

    this.mark(this.sections[0].link)
    this.onScroll = () => this.update()
    // A tap on a tab should light it up at once, before the scroll settles.
    this.linkTargets.forEach((a) => a.addEventListener("click", () => this.mark(a)))
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.update()
  }

  disconnect() {
    if (this.onScroll) window.removeEventListener("scroll", this.onScroll)
  }

  // The section whose heading is closest above the top third of the viewport.
  update() {
    const line = window.innerHeight / 3
    let current = this.sections[0]
    for (const s of this.sections) {
      if (s.el.getBoundingClientRect().top <= line) current = s
    }
    this.mark(current.link)
  }

  mark(link) {
    if (link === this.current) return
    this.current = link
    this.linkTargets.forEach((a) => a.classList.toggle("active", a === link))
  }
}
