import { Controller } from "@hotwired/stimulus"

// Member multi-purpose scanner. Reads a QR (URL or bare token) and navigates to
// the resolve endpoint, which auto-detects promo-claim vs POS-earn.
export default class extends Controller {
  static targets = ["video", "status", "overlay"]
  static values = {
    resolveUrl: String,
    scanningText: String, deniedText: String, unsupportedText: String, failedText: String
  }

  async connect() {
    // Ask the browser what the real camera-permission state is. When it's
    // already "granted" we auto-start with no prompt; when it's "prompt" we
    // keep the overlay so getUserMedia fires on the user's tap (fewer surprise
    // prompts, and iOS is happier). "denied" shows how to re-enable. When the
    // Permissions API can't answer (Safari/iOS often can't for camera) we fall
    // back to the localStorage heuristic.
    const state = await this.cameraState()
    if (state === "granted") {
      if (this.hasOverlayTarget) this.overlayTarget.style.display = "none"
      this.start()
    } else if (state === "denied") {
      if (this.hasOverlayTarget) this.overlayTarget.style.display = ""
      this.statusTarget.textContent = this.deniedTextValue
    } else if (state === "prompt") {
      if (this.hasOverlayTarget) this.overlayTarget.style.display = ""
    } else {
      if (this.cameraSeen() && this.hasOverlayTarget) this.overlayTarget.style.display = "none"
      this.start()
    }
    this.watchPermission()
    document.addEventListener("visibilitychange", this.visibility)
  }

  async cameraState() {
    try {
      if (navigator.permissions?.query) {
        this._perm = await navigator.permissions.query({ name: "camera" })
        return this._perm.state // "granted" | "prompt" | "denied"
      }
    } catch (e) { /* camera not a queryable name (iOS/Safari) */ }
    return null
  }

  // Auto-start the moment the user grants access from the browser UI.
  watchPermission() {
    if (!this._perm) return
    this._perm.onchange = () => {
      if (this._perm.state === "granted" && !this.stream) { this.start() }
    }
  }

  cameraSeen() { try { return localStorage.getItem("qrnavCameraOk") === "1" } catch (e) { return false } }
  rememberCamera(ok) { try { ok ? localStorage.setItem("qrnavCameraOk", "1") : localStorage.removeItem("qrnavCameraOk") } catch (e) {} }

  async start() {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.statusTarget.textContent = this.unsupportedTextValue
      return
    }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } })
      this.videoTarget.srcObject = this.stream
      this.videoTarget.setAttribute("playsinline", "true")
      await this.videoTarget.play()
      if (this.hasOverlayTarget) this.overlayTarget.style.display = "none"
      this.rememberCamera(true)

      if ("BarcodeDetector" in window) {
        this.mode = "native"
        this.detector = new BarcodeDetector({ formats: ["qr_code"] })
      } else {
        // Fallback for iOS/older browsers: decode frames with jsQR.
        this.mode = "jsqr"
        this.jsqr = (await import("jsqr")).default || window.jsQR
        this.canvas = document.createElement("canvas")
      }
      this.statusTarget.textContent = this.scanningTextValue
      this.timer = setInterval(() => this.tick(), this.mode === "jsqr" ? 250 : 400)
    } catch (e) {
      // Access failed/denied — restore the overlay button so the user can retry.
      this.rememberCamera(false)
      if (this.hasOverlayTarget) this.overlayTarget.style.display = ""
      this.statusTarget.textContent = this.failedTextValue
    }
  }

  async tick() {
    try {
      if (this.mode === "native") {
        const codes = await this.detector.detect(this.videoTarget)
        if (codes.length) { this.stop(); this.go(codes[0].rawValue) }
      } else {
        const v = this.videoTarget
        if (!v.videoWidth) return
        this.canvas.width = v.videoWidth
        this.canvas.height = v.videoHeight
        const ctx = this.canvas.getContext("2d", { willReadFrequently: true })
        ctx.drawImage(v, 0, 0, this.canvas.width, this.canvas.height)
        const img = ctx.getImageData(0, 0, this.canvas.width, this.canvas.height)
        const res = this.jsqr(img.data, img.width, img.height, { inversionAttempts: "dontInvert" })
        if (res && res.data) { this.stop(); this.go(res.data) }
      }
    } catch (e) { /* transient */ }
  }

  go(value) {
    value = (value || "").trim()
    try {
      const u = new URL(value)
      if (u.origin === location.origin) { window.location.href = value; return }
    } catch (e) { /* not a URL */ }
    window.location.href = `${this.resolveUrlValue}?code=${encodeURIComponent(value)}`
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    if (this.stream) this.stream.getTracks().forEach((t) => t.stop())
    this.stream = null // so coming back to the tab can start a fresh one
  }

  // Decoding every frame with the camera live is the most expensive thing this
  // app does on a phone; there is nothing to scan while the screen is off.
  visibility = () => {
    if (document.hidden) { this.stop() } else if (!this.stream) { this.start() }
  }

  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.visibility)
  }
}
