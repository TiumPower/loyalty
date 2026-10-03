import { Controller } from "@hotwired/stimulus"

// Customer PWA glue: registers the service worker, manages Web Push
// subscription (opt-in), and drives the "Add to Home Screen" banner.
export default class extends Controller {
  static values = { vapid: String, subscribeUrl: String, unsubscribeUrl: String }
  static targets = ["installBanner", "installButton", "laterButton", "iosHint", "pushToggle", "pushLabel", "pushBanner"]

  connect() {
    this.registerSW().then(() => { this.reflectPush(); this.setupPushPrompt() })
    this.setupInstall()
  }

  async registerSW() {
    if (!("serviceWorker" in navigator)) return
    try { await navigator.serviceWorker.register("/service-worker.js") } catch (e) {}
  }

  // ---------- Web Push ----------
  supported() { return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window }

  async currentSub() {
    try { const r = await navigator.serviceWorker.ready; return await r.pushManager.getSubscription() }
    catch (e) { return null }
  }

  async reflectPush() {
    if (!this.hasPushLabelTarget) return
    if (!this.supported()) return this.setPush("unsupported")
    if (Notification.permission === "denied") return this.setPush("blocked")
    const sub = await this.currentSub()
    this.setPush(sub ? "on" : "off")
    if (sub) this.resync(sub)
  }

  // Công tắc trước đây chỉ đọc trạng thái của TRÌNH DUYỆT. Nếu lần lưu lên máy
  // chủ hỏng — phiên đăng nhập hết hạn, mạng rớt giữa chừng — thì trình duyệt
  // vẫn có subscription, công tắc vẫn "Bật", mà máy chủ không có dòng nào để
  // gửi tới. Không có cách nào để khách biết, và cũng không có cách nào tự
  // khỏi: bật lại thì thấy "đang bật" rồi nên bấm vào là TẮT.
  //
  // Nên mỗi phiên gửi lại một lần (store! là ghi đè theo endpoint, gửi lại
  // không tạo bản trùng). Máy đang hỏng tự lành ở lần mở app kế tiếp.
  async resync(sub) {
    try {
      if (sessionStorage.getItem("push_resynced") === "1") return
      sessionStorage.setItem("push_resynced", "1")
    } catch (e) {}
    const ok = await this.save(sub)
    if (!ok) this.setPush("off")
  }

  setPush(state) {
    this.pushState = state
    if (this.hasPushToggleTarget) {
      const knob = this.pushToggleTarget.querySelector(".knob")
      // No slide animation on the initial (async) state — avoids a blink on load.
      if (!this._reflected && knob) {
        this.pushToggleTarget.style.transition = "none"
        knob.style.transition = "none"
      }
      this.pushToggleTarget.classList.toggle("on", state === "on")
      if (!this._reflected && knob) {
        void this.pushToggleTarget.offsetWidth
        this.pushToggleTarget.style.transition = ""
        knob.style.transition = ""
        this._reflected = true
      }
    }
    if (this.hasPushLabelTarget) {
      this.pushLabelTarget.textContent =
        this.data.get(`${state}Text`) || this.data.get("offText") || ""
    }
  }

  async togglePush() {
    if (!this.supported()) return
    if (this.pushState === "blocked") { alert(this.data.get("blockedText")); return }
    const existing = await this.currentSub()
    if (existing) { await this.unsub(existing); this.setPush("off"); return }
    await this.subscribe()
  }

  async subscribe() {
    const perm = await Notification.requestPermission()
    if (perm !== "granted") return this.reflectPush()
    let sub
    try {
      const reg = await navigator.serviceWorker.ready
      sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: this.b64(this.vapidValue) })
    } catch (e) { return this.reflectPush() }

    // Máy chủ không nhận được thì ĐỪNG báo là đã bật. Bản cũ gửi xong là bật
    // công tắc bất kể kết quả, nên một lần lưu hỏng biến thành một cái công tắc
    // nói dối vĩnh viễn.
    if (await this.save(sub)) {
      this.setPush("on")
    } else {
      try { await sub.unsubscribe() } catch (e) {}
      this.setPush("off")
      alert(this.data.get("failedText") || "")
    }
  }

  // Chỉ coi là xong khi máy chủ trả đúng {ok:true}. Không dùng `res.ok` một
  // mình: phiên đăng nhập hết hạn thì fetch đi theo chuyển hướng và kết thúc ở
  // trang đăng nhập với mã 200 — "thành công" theo nghĩa HTTP, mà chẳng có gì
  // được lưu.
  async save(sub) {
    try {
      const res = await this.post(this.subscribeUrlValue, sub.toJSON())
      const data = await res.json()
      return res.ok && data && data.ok === true
    } catch (e) {
      return false
    }
  }

  async unsub(sub) {
    await this.post(this.unsubscribeUrlValue, { endpoint: sub.endpoint })
    try { await sub.unsubscribe() } catch (e) {}
  }

  async post(url, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    return fetch(url, {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token || "" },
      body: JSON.stringify(body),
    })
  }

  b64(base64) {
    const pad = "=".repeat((4 - (base64.length % 4)) % 4)
    const raw = atob((base64 + pad).replace(/-/g, "+").replace(/_/g, "/"))
    return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)))
  }

  // ---------- Encourage enabling notifications ----------
  static PUSH_SNOOZE_MS = 7 * 24 * 60 * 60 * 1000

  setupPushPrompt() {
    if (!this.hasPushBannerTarget) return
    if (!this.supported()) return
    if (Notification.permission !== "default") return // already granted/denied
    if (this.pushSnoozed()) return
    const standalone = window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone
    const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent)
    // iOS only supports Web Push from the installed (home-screen) PWA — in
    // Safari the install banner nudges that first, so skip the push prompt.
    if (isIos && !standalone) return
    setTimeout(async () => {
      if (await this.currentSub()) return
      // Don't stack on top of the install banner.
      if (this.hasInstallBannerTarget && !this.installBannerTarget.hidden) return
      this.pushBannerTarget.hidden = false
    }, 4500)
  }

  async enablePush() {
    this.pushBannerTarget.hidden = true
    this.pushSnooze()
    await this.subscribe()
  }

  dismissPush() {
    this.pushSnooze()
    if (this.hasPushBannerTarget) this.pushBannerTarget.hidden = true
  }

  pushSnoozed() {
    try { return Date.now() < parseInt(localStorage.getItem("push_snooze") || "0", 10) } catch (e) { return false }
  }

  pushSnooze() {
    try { localStorage.setItem("push_snooze", String(Date.now() + this.constructor.PUSH_SNOOZE_MS)) } catch (e) {}
  }

  // ---------- Add to Home Screen (popup, shown at most once / 7 days) ----------
  static SNOOZE_MS = 7 * 24 * 60 * 60 * 1000

  setupInstall() {
    if (!this.hasInstallBannerTarget) return
    const standalone = window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone
    if (standalone || this.snoozed()) return

    window.addEventListener("beforeinstallprompt", (e) => {
      e.preventDefault()
      this.deferred = e
      this.showLater()
    })

    // iOS Safari has no beforeinstallprompt — show manual instructions and turn
    // the single remaining button into a clear "Got it" primary (not just Later).
    const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent)
    if (isIos && this.hasIosHintTarget) {
      this.iosHintTarget.hidden = false
      if (this.hasInstallButtonTarget) this.installButtonTarget.hidden = true
      if (this.hasLaterButtonTarget) {
        this.laterButtonTarget.textContent = this.data.get("gotItText") || this.laterButtonTarget.textContent
        this.laterButtonTarget.classList.remove("l-btn-ghost")
        this.laterButtonTarget.classList.add("l-btn-primary")
      }
      this.showLater()
    }
  }

  // Delay so it doesn't block the first paint; only once per page load.
  showLater() {
    if (this._shown) return
    this._shown = true
    setTimeout(() => { this.installBannerTarget.hidden = false }, 2500)
  }

  async install() {
    this.installBannerTarget.hidden = true
    this.snooze()
    if (!this.deferred) return
    this.deferred.prompt()
    await this.deferred.userChoice
    this.deferred = null
  }

  dismissInstall() {
    this.snooze()
    if (this.hasInstallBannerTarget) this.installBannerTarget.hidden = true
  }

  snoozed() {
    try { return Date.now() < parseInt(localStorage.getItem("a2hs_snooze") || "0", 10) } catch (e) { return false }
  }

  snooze() {
    try { localStorage.setItem("a2hs_snooze", String(Date.now() + this.constructor.SNOOZE_MS)) } catch (e) {}
  }
}
