import { Controller } from "@hotwired/stimulus"

// "0.5 km away", from the design's shop page.
//
// The customer's position never leaves their phone: the branch coordinates are
// already in the page, so the distance is worked out here and nothing is sent
// anywhere. Asking on page load would be rude, so the first time it takes a tap;
// after the browser has granted the permission it resolves silently.
export default class extends Controller {
  static targets = ["place", "ask", "status"]
  static values = { kmLabel: String, mLabel: String, failed: String }

  async connect() {
    if (!navigator.geolocation) return this.hideAsk()
    try {
      const p = await navigator.permissions?.query({ name: "geolocation" })
      if (p?.state === "granted") this.locate({ silent: true })
    } catch (e) { /* not queryable — leave the button up */ }
  }

  locate({ silent = false } = {}) {
    if (!navigator.geolocation) return
    if (!silent && this.hasStatusTarget) this.statusTarget.hidden = false
    navigator.geolocation.getCurrentPosition(
      (pos) => this.render(pos.coords.latitude, pos.coords.longitude),
      () => { if (!silent) this.fail() },
      { enableHighAccuracy: false, timeout: 8000, maximumAge: 300000 }
    )
  }

  render(lat, lng) {
    this.placeTargets.forEach((el) => {
      const d = this.haversine(lat, lng, parseFloat(el.dataset.lat), parseFloat(el.dataset.lng))
      const out = el.querySelector("[data-role='dist']")
      if (out && isFinite(d)) out.textContent = this.format(d)
    })
    this.hideAsk()
    if (this.hasStatusTarget) this.statusTarget.hidden = true
  }

  fail() {
    if (this.hasStatusTarget) {
      this.statusTarget.hidden = false
      this.statusTarget.textContent = this.failedValue
    }
  }

  hideAsk() { this.askTargets.forEach((b) => { b.hidden = true }) }

  // Under a kilometre people think in metres, and rounding to the nearest 10m
  // avoids implying a precision phone GPS does not have.
  format(km) {
    if (km < 1) return this.mLabelValue.replace("%{n}", String(Math.max(10, Math.round(km * 1000 / 10) * 10)))
    return this.kmLabelValue.replace("%{n}", km.toFixed(1).replace(".", ","))
  }

  haversine(lat1, lon1, lat2, lon2) {
    const R = 6371, rad = (d) => (d * Math.PI) / 180
    const dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1)
    const a = Math.sin(dLat / 2) ** 2 +
              Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2
    return 2 * R * Math.asin(Math.sqrt(a))
  }
}
