import { Controller } from "@hotwired/stimulus"

// Counts a code's validity down and only then offers "resend", so people are
// not invited to request a second code while the first is still on its way.
export default class extends Controller {
  static targets = ["clock", "waiting", "resend"]
  static values = { seconds: { type: Number, default: 60 } }

  connect() {
    this.left = this.secondsValue
    this.render()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() { if (this.timer) clearInterval(this.timer) }

  tick() {
    this.left -= 1
    if (this.left <= 0) {
      clearInterval(this.timer)
      this.left = 0
      if (this.hasWaitingTarget) this.waitingTarget.hidden = true
      if (this.hasResendTarget) this.resendTarget.hidden = false
    }
    this.render()
  }

  render() {
    if (!this.hasClockTarget) return
    const m = Math.floor(this.left / 60)
    const s = String(this.left % 60).padStart(2, "0")
    this.clockTarget.textContent = `${m}:${s}`
  }
}
