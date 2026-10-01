import { Controller } from "@hotwired/stimulus"

// "Mã của tôi": rotates the personal QR on a countdown (so a screenshot can't be
// reused) and polls for a fresh earn to reveal a "+X điểm" burst on the phone.
export default class extends Controller {
  static targets = ["qr", "count", "burst", "burstPoints", "burstPts2", "burstBalance",
                    "burstShop", "burstAt", "burstAmount", "burstBillRow"]
  static values = { tokenUrl: String, recentUrl: String, after: Number, ttl: Number, locale: String }

  connect() {
    this.remaining = this.ttlValue
    this.run()
    // This is the screen customers leave open at the counter and then pocket.
    // Polling every three seconds behind a locked screen is work nobody sees.
    document.addEventListener("visibilitychange", this.visibility)
  }

  run() {
    this.halt()
    this.countdown = setInterval(() => this.tick(), 1000)
    this.poller = setInterval(() => this.pollEarn(), 3000)
  }

  halt() {
    clearInterval(this.countdown)
    clearInterval(this.poller)
  }

  visibility = () => {
    if (document.hidden) { this.halt(); return }
    // Coming back with the result still on screen: leave it alone. Rotating the
    // QR and polling behind it is how the burst used to get overwritten.
    if (this.showing) return
    // Back on screen: the code has almost certainly gone stale, so take a fresh
    // one rather than showing one the counter will reject.
    this.remaining = this.ttlValue
    this.rotate()
    this.run()
  }

  disconnect() {
    this.halt()
    document.removeEventListener("visibilitychange", this.visibility)
  }

  tick() {
    this.remaining -= 1
    if (this.remaining <= 0) { this.rotate(); this.remaining = this.ttlValue }
    if (this.hasCountTarget) this.countTarget.textContent = this.remaining
  }

  async rotate() {
    try {
      const res = await fetch(this.tokenUrlValue, { headers: { Accept: "application/json" } })
      const data = await res.json()
      if (data.svg) this.qrTarget.innerHTML = data.svg
    } catch (e) { /* keep old QR */ }
  }

  async pollEarn() {
    try {
      const res = await fetch(`${this.recentUrlValue}?after=${this.afterValue}`,
                             { headers: { Accept: "application/json" } })
      const data = await res.json()
      // A request already in flight when the burst went up would otherwise
      // reveal a second time over the one being read.
      if (data.id) this.afterValue = data.id
      if (data.earned && !this.showing) this.reveal(data)
    } catch (e) { /* ignore */ }
  }

  reveal(data) {
    this.showing = true
    // Was pinned to vi-VN, so an English customer saw "1.234" for 1,234.
    const loc = this.hasLocaleValue && this.localeValue ? this.localeValue : "vi-VN"
    const points = data.earned.toLocaleString(loc)
    this.burstPointsTarget.textContent = points
    if (this.hasBurstPts2Target) this.burstPts2Target.textContent = `+${points}`
    this.burstBalanceTarget.textContent = data.balance.toLocaleString(loc)

    // The receipt half. Each piece is drawn only when the server sent it —
    // a branch the shop never named, or a check-in with no bill behind it,
    // must not leave an empty row looking like missing data.
    if (this.hasBurstShopTarget && data.shop) {
      this.burstShopTarget.textContent = data.outlet ? `${data.shop} · ${data.outlet}` : data.shop
    }
    if (this.hasBurstAtTarget) this.burstAtTarget.textContent = data.at || ""
    if (this.hasBurstBillRowTarget) {
      const hasBill = Boolean(data.amount)
      this.burstBillRowTarget.hidden = !hasBill
      if (hasBill && this.hasBurstAmountTarget) this.burstAmountTarget.textContent = data.amount
    }

    const el = this.burstTarget
    el.style.display = "flex"
    el.scrollTop = 0
    el.animate([{ opacity: 0, transform: "scale(1.15)" }, { opacity: 1, transform: "scale(1)" }],
               { duration: 300, easing: "ease-out" })
    if (navigator.vibrate) navigator.vibrate(60)
    // Keep the result on screen until the customer taps OK (or leaves) — pause
    // the QR rotation + earn polling so nothing overwrites it behind the burst.
    this.halt()
  }

  // Tap "OK": hide the result and resume the rotating QR + earn polling.
  dismiss() {
    this.showing = false
    const el = this.burstTarget
    el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 300 }).onfinish = () => { el.style.display = "none" }
    this.remaining = this.ttlValue
    this.rotate()
    this.run()
  }
}
