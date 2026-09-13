import { Controller } from "@hotwired/stimulus"
import "jsqr" // UMD side-effect: defines window.jsQR (fallback decoder for iOS/Safari)

// Counter-side QR scanner. Uses the native BarcodeDetector when available
// (Android Chrome), otherwise falls back to jsQR decoding video frames on a
// canvas (iOS Safari & Chrome, which have no BarcodeDetector). On a successful
// decode it fills the hidden token field and submits the lookup form.
export default class extends Controller {
  static targets = ["video", "token", "form", "status", "overlay"]

  async connect() {
    // Prefer the real permission state (auto-start only when already granted);
    // fall back to the localStorage heuristic when the browser can't answer.
    const state = await this.cameraState()
    if (state === "granted") {
      if (this.hasOverlayTarget) this.overlayTarget.style.display = "none"
      this.start()
    } else if (state === "denied") {
      if (this.hasOverlayTarget) this.overlayTarget.style.display = ""
      this.statusTarget.textContent = "Camera đang bị chặn — bật lại quyền trong cài đặt trình duyệt, hoặc nhập mã thủ công."
    } else if (state === "prompt") {
      if (this.hasOverlayTarget) this.overlayTarget.style.display = ""
    } else {
      if (this.cameraSeen() && this.hasOverlayTarget) this.overlayTarget.style.display = "none"
      this.start()
    }
    this.watchPermission()
  }

  async cameraState() {
    try {
      if (navigator.permissions?.query) {
        this._perm = await navigator.permissions.query({ name: "camera" })
        return this._perm.state
      }
    } catch (e) { /* not queryable */ }
    return null
  }

  watchPermission() {
    if (!this._perm) return
    this._perm.onchange = () => {
      if (this._perm.state === "granted" && !this.stream) this.start()
    }
  }

  cameraSeen() { try { return localStorage.getItem("scannerCameraOk") === "1" } catch (e) { return false } }
  rememberCamera(ok) { try { ok ? localStorage.setItem("scannerCameraOk", "1") : localStorage.removeItem("scannerCameraOk") } catch (e) {} }

  // Which decode engine can we use? Native first, jsQR fallback second.
  decodeMode() {
    if ("BarcodeDetector" in window) return "native"
    if (typeof window.jsQR === "function") return "jsqr"
    return null
  }

  async start() {
    const mode = this.decodeMode()
    if (!mode) {
      this.statusTarget.textContent = "Trình duyệt không hỗ trợ quét — hãy nhập mã thủ công bên dưới."
      return
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      this.statusTarget.textContent = "Không truy cập được camera — hãy nhập mã thủ công."
      return
    }
    this.statusTarget.textContent = "Đang mở camera…"
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: "environment" } }, audio: false
      })
      this.videoTarget.srcObject = this.stream
      // iOS needs the inline/muted attributes (already set) + an explicit play().
      this.videoTarget.setAttribute("playsinline", "")
      await this.videoTarget.play()
      if (this.hasOverlayTarget) this.overlayTarget.style.display = "none"
      this.rememberCamera(true)
      this.statusTarget.textContent = "Đang quét…"

      if (mode === "native") {
        this.detector = new BarcodeDetector({ formats: ["qr_code"] })
      } else {
        this.canvas = document.createElement("canvas")
        this.ctx = this.canvas.getContext("2d", { willReadFrequently: true })
      }
      this.mode = mode
      this.timer = setInterval(() => this.tick(), 300)
    } catch (e) {
      this.rememberCamera(false)
      if (this.hasOverlayTarget) this.overlayTarget.style.display = ""
      this.statusTarget.textContent = this.cameraError(e)
    }
  }

  // Every camera failure used to read "Không truy cập được camera" — the same
  // sentence whether the cashier had denied permission (fixable in seconds),
  // the phone has no camera, or another app is holding it. Say which.
  cameraError(e) {
    switch (e && e.name) {
      case "NotAllowedError":
      case "SecurityError":
        return "Camera đang bị chặn. Bấm vào biểu tượng 🔒 trên thanh địa chỉ → cho phép Camera, rồi tải lại trang. Hoặc nhập mã thủ công bên dưới."
      case "NotFoundError":
      case "OverconstrainedError":
        return "Không tìm thấy camera trên thiết bị này — hãy nhập mã thủ công bên dưới."
      case "NotReadableError":
        return "Camera đang được ứng dụng khác sử dụng. Đóng ứng dụng đó rồi thử lại, hoặc nhập mã thủ công."
      default:
        return "Không mở được camera — hãy nhập mã thủ công bên dưới."
    }
  }

  async tick() {
    try {
      const raw = this.mode === "native" ? await this.detectNative() : this.detectJsQR()
      if (!raw) return
      // The lookup response re-renders this frame (a fresh scanner instance),
      // which would instantly re-detect the same QR still in view — a tight
      // resubmit loop. Dedupe identical scans across instances for a few
      // seconds via window state (survives the Turbo frame swap).
      const now = Date.now()
      if (raw === window.__lastScan && now - (window.__lastScanAt || 0) < 3500) return
      window.__lastScan = raw
      window.__lastScanAt = now
      this.stop()
      this.tokenTarget.value = raw
      this.formTarget.requestSubmit()
    } catch (e) { /* transient */ }
  }

  async detectNative() {
    const codes = await this.detector.detect(this.videoTarget)
    return codes.length ? (codes[0].rawValue || "").trim() : null
  }

  detectJsQR() {
    const v = this.videoTarget
    const w = v.videoWidth, h = v.videoHeight
    if (!w || !h) return null
    this.canvas.width = w
    this.canvas.height = h
    this.ctx.drawImage(v, 0, 0, w, h)
    const img = this.ctx.getImageData(0, 0, w, h)
    const code = window.jsQR(img.data, w, h, { inversionAttempts: "dontInvert" })
    return code && code.data ? code.data.trim() : null
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    if (this.stream) this.stream.getTracks().forEach((t) => t.stop())
  }

  disconnect() { this.stop() }
}
