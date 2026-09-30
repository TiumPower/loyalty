import { Controller } from "@hotwired/stimulus"
import rough from "roughjs"

// Hand-drawn doodles for the marketing pages, drawn with Rough.js into the
// element's own <svg>:  <svg data-controller="sketch" data-sketch-shape-value="cup">
// Strokes are currentColor (set the ink with a text-* class); fills are pencil
// hatching in kraft. Each recipe has a fixed seed, so every visit draws the same
// doodle. Every path gets pathLength=1, which lets CSS draw it in on reveal
// (see [data-reveal="sketch"] in application.css). "frame" sizes itself to the
// element and redraws on resize; the rest use their own viewBox.
const KRAFT = "#c0ffee" // placeholder colour, swapped for var(--kraft) after drawing
const PI = Math.PI

const RECIPES = {
  "paper-card": [80, 64, (rc, o) => [
    rc.rectangle(8, 12, 60, 42, { ...o, fill: KRAFT }),
    ...[20, 32, 44, 56].flatMap((x, i) => [
      rc.circle(x, 28, 8, i < 3 ? { ...o, fill: "currentColor", fillStyle: "solid", strokeWidth: 1 } : o),
      rc.circle(x, 42, 8, o)
    ])
  ]],
  cup: [72, 72, (rc, o) => [
    rc.path("M15 28 L55 28 L50 62 Q49 67 44 67 L26 67 Q21 67 20 62 Z", { ...o, fill: KRAFT }),
    rc.arc(55, 42, 18, 20, -PI / 2, PI / 2, false, o),
    rc.curve([[26, 22], [23, 15], [28, 9], [25, 3]], o),
    rc.curve([[37, 22], [34, 15], [39, 9], [36, 3]], o),
    rc.curve([[48, 22], [45, 15], [50, 9], [47, 3]], o)
  ]],
  shopfront: [84, 72, (rc, o) => [
    rc.rectangle(8, 12, 68, 12, { ...o, fill: KRAFT }),
    rc.path("M8 24 Q16 34 25 24 Q33 34 42 24 Q50 34 59 24 Q67 34 76 24", o),
    rc.rectangle(13, 30, 58, 36, o),
    rc.rectangle(34, 42, 16, 24, { ...o, fill: KRAFT }),
    rc.rectangle(18, 36, 11, 11, o),
    rc.rectangle(55, 36, 11, 11, o)
  ]],
  chalkboard: [80, 72, (rc, o) => [
    rc.line(22, 44, 12, 70, o), rc.line(58, 44, 68, 70, o), rc.line(40, 44, 40, 64, o),
    rc.rectangle(10, 6, 60, 40, { ...o, fill: KRAFT }),
    rc.curve([[18, 18], [30, 15], [44, 19], [52, 16]], o),
    rc.curve([[18, 27], [28, 25], [38, 28], [46, 26]], o),
    rc.curve([[18, 36], [32, 34], [42, 37], [58, 35]], o)
  ]],
  "price-tag": [80, 64, (rc, o) => [
    rc.path("M12 20 L42 8 L70 34 L40 56 Z", { ...o, fill: KRAFT }),
    rc.circle(26, 20, 8, o),
    rc.curve([[26, 20], [16, 10], [8, 14], [4, 4]], o)
  ]],
  question: [72, 64, (rc, o) => [
    rc.ellipse(36, 28, 60, 42, { ...o, fill: KRAFT }),
    rc.path("M20 44 L12 60 L32 48", o),
    rc.path("M29 22 Q29 14 36 14 Q43 14 43 21 Q43 26 36 28 L36 33", { ...o, strokeWidth: 2 }),
    rc.circle(36, 39, 3, { ...o, fill: "currentColor", fillStyle: "solid" })
  ]],
  // Quenly's four-point star, with two small sparks: the hero's mark of "reward"
  sparkle: [96, 80, (rc, o) => [
    rc.path("M40 8 C43 30 50 37 72 40 C50 43 43 50 40 72 C37 50 30 43 8 40 C30 37 37 30 40 8 Z", { ...o, fill: KRAFT }),
    rc.path("M80 10 C81 17 83 19 90 20 C83 21 81 23 80 30 C79 23 77 21 70 20 C77 19 79 17 80 10 Z", o),
    rc.circle(84, 56, 5, { ...o, fill: "currentColor", fillStyle: "solid" })
  ]],
  heart: [28, 24, (rc, o) => [
    rc.path("M14 21 C4 14 2 9 5 5 C8 2 12 3 14 7 C16 3 20 2 23 5 C26 9 24 14 14 21 Z", { ...o, fill: "currentColor", fillStyle: "hachure", hachureGap: 2.5 })
  ]],
  arrow: [120, 72, (rc, o) => [
    rc.curve([[6, 60], [38, 64], [78, 44], [106, 14]], o),
    rc.linearPath([[92, 14], [106, 13], [104, 27]], o)
  ]],
  underline: [200, 16, (rc, o) => [
    rc.curve([[4, 10], [60, 6], [130, 11], [196, 5]], { ...o, strokeWidth: 2.2, roughness: 1.6 })
  ]],
  circle: [120, 56, (rc, o) => [rc.ellipse(60, 28, 112, 48, { ...o, strokeWidth: 1.8 })]],
  check: [24, 24, (rc, o) => [rc.linearPath([[4, 13], [10, 19], [21, 5]], { ...o, strokeWidth: 2 })]],
  cross: [24, 24, (rc, o) => [rc.line(6, 6, 18, 18, o), rc.line(18, 6, 6, 18, o)]],
  frame: [0, 0, (rc, o, w, h) => [rc.rectangle(4, 4, w - 8, h - 8, { ...o, roughness: 1.1, bowing: .6 })]]
}

export default class extends Controller {
  static values = { shape: String, seed: { type: Number, default: 7 } }

  connect() {
    this.draw()
    if (this.shapeValue === "frame") {
      this.resize = new ResizeObserver(() => this.draw())
      this.resize.observe(this.element)
    }
  }

  disconnect() { this.resize?.disconnect() }

  draw() {
    const recipe = RECIPES[this.shapeValue]
    if (!recipe) return
    let [w, h, make] = recipe
    if (this.shapeValue === "frame") ({ width: w, height: h } = this.element.getBoundingClientRect())
    if (!w || !h) return

    const svg = this.element
    svg.replaceChildren()
    svg.setAttribute("viewBox", `0 0 ${w} ${h}`)
    const rc = rough.svg(svg)
    const opts = { seed: this.seedValue, stroke: "currentColor", strokeWidth: 1.6, roughness: 1.3, bowing: 1.2,
                   fillStyle: "hachure", hachureGap: 4, hachureAngle: -41, fillWeight: .9 }
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("filter", "url(#ink)")
    make(rc, opts, w, h).forEach((node) => g.append(node))
    g.querySelectorAll(`[stroke="${KRAFT}"]`).forEach((p) => { p.removeAttribute("stroke"); p.style.stroke = "var(--kraft)" })
    g.querySelectorAll(`[fill="${KRAFT}"]`).forEach((p) => { p.removeAttribute("fill"); p.style.fill = "var(--kraft)" })
    g.querySelectorAll("path").forEach((p) => p.setAttribute("pathLength", "1"))
    svg.append(g)
  }
}
