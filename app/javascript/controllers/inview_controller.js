import { Controller } from "@hotwired/stimulus"

// Marketing section entrances. Marks [data-reveal] descendants with .is-in as
// they scroll into view; the CSS does the motion. The hidden start state is
// .reveal-on on <html>, set by an inline script in layouts/marketing before
// first paint; with reduced motion, or if this never connects, it is absent.
export default class extends Controller {
  connect() {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window)) return
    document.documentElement.dataset.inview = "1"
    this.io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting) return
        e.target.classList.add("is-in")
        this.io.unobserve(e.target)
      })
    }, { rootMargin: "0px 0px -8% 0px" })
    this.element.querySelectorAll("[data-reveal]").forEach((el) => this.io.observe(el))
  }

  disconnect() { this.io?.disconnect() }
}
