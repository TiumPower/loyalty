import { Controller } from "@hotwired/stimulus"

// The paper "buy 9 get 1" card on the landing hero. Each press inks the next
// slot with a slightly rotated stamp; the ninth fills the card, the next press
// clears it. Stamps already in the markup count as collected.
// Until the visitor presses it themselves, the card demos itself once: a
// stamp every beat until the card is full, then it stops.
export default class extends Controller {
  static targets = ["slot", "tpl", "count", "bar"] // count/bar: the phone's stamp row, kept in step

  connect() {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return
    this.start = setTimeout(() => { this.demo = setInterval(() => this.tick(), 1300) }, 2600)
  }

  disconnect() { this.stop() }

  press() {
    this.stop()
    this.stamp()
  }

  tick() {
    if (this.count >= 9) return this.stop()
    this.stamp()
  }

  stamp() {
    if (this.count >= 9) return this.reset()

    const mark = this.tplTarget.content.firstElementChild.cloneNode(true)
    mark.style.rotate = `${Math.round(Math.random() * 36 - 18)}deg`
    this.slotTargets[this.count].append(mark)
    if (this.count === 9) this.element.classList.add("is-full")
    this.sync()
  }

  reset() {
    this.element.querySelectorAll(".l-stamp").forEach((s) => s.remove())
    this.element.classList.remove("is-full")
    this.sync()
  }

  sync() {
    if (this.hasCountTarget) this.countTarget.textContent = this.count
    if (this.hasBarTarget) this.barTarget.style.width = `${(this.count / 9) * 100}%`
  }

  stop() {
    clearTimeout(this.start)
    clearInterval(this.demo)
  }

  get count() { return this.element.querySelectorAll(".l-stamp").length }
}
