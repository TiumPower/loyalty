import { Controller } from "@hotwired/stimulus"

// Busy-hour panel: switch branch (GET) and refresh the AI suggestion (POST)
// over AJAX — no page reload. Also shows a hover tooltip with the real purchase
// count for each heatmap cell.
export default class extends Controller {
  static targets = ["panel", "outlet", "refreshBtn", "rangeSelect", "fromDate", "toDate"]
  static values = { url: String, refreshUrl: String, range: String }

  connect() { this.bindTooltip() }

  outlet() { return this.hasOutletTarget ? this.outletTarget.value : "" }

  // Build query from the panel's outlet + range + custom dates.
  params() {
    const p = new URLSearchParams({ outlet: this.outlet() })
    const from = this.hasFromDateTarget ? this.fromDateTarget.value : ""
    const to   = this.hasToDateTarget ? this.toDateTarget.value : ""
    if (from || to) { if (from) p.set("from", from); if (to) p.set("to", to) }
    else p.set("range", this.hasRangeSelectTarget ? this.rangeSelectTarget.value : this.rangeValue)
    return p
  }

  // Branch / range / date change → reload the panel.
  async switch() {
    await this.swap(() => fetch(`${this.urlValue}?${this.params()}`, { headers: { "Accept": "text/html" } }))
  }

  // Changing the range preset clears any custom dates so it takes effect.
  async rangeChanged() {
    if (this.hasFromDateTarget) this.fromDateTarget.value = ""
    if (this.hasToDateTarget) this.toDateTarget.value = ""
    await this.switch()
  }

  // Refresh button → (re)generate the AI insight for the current view.
  async refresh() {
    if (this.hasRefreshBtnTarget) {
      this.refreshBtnTarget.disabled = true
      this.refreshBtnTarget.textContent = "⏳ Đang tạo gợi ý…"
    }
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const resp = await this.swap(() => fetch(`${this.refreshUrlValue}?${this.params()}`, {
      method: "POST",
      headers: { "X-CSRF-Token": token, "Accept": "text/html" }
    }))
    // The server refuses to re-run the model within its cooldown. Without a word
    // the panel just redraws the same sentence and the click looks broken.
    if (resp && resp.headers.get("X-Insight-Cooldown") && this.hasRefreshBtnTarget) {
      this.refreshBtnTarget.disabled = true
      this.refreshBtnTarget.textContent = "Gợi ý vừa được tạo"
      setTimeout(() => {
        if (!this.hasRefreshBtnTarget) return
        this.refreshBtnTarget.disabled = false
        this.refreshBtnTarget.textContent = "🔄 Làm mới gợi ý"
      }, 4000)
    }
  }

  async swap(request) {
    this.setLoading(true)
    try {
      const resp = await request()
      if (!resp.ok) throw new Error(resp.status)
      this.panelTarget.innerHTML = await resp.text()
      this.bindTooltip()
      return resp
    } catch (e) {
      if (this.hasRefreshBtnTarget) {
        this.refreshBtnTarget.disabled = false
        this.refreshBtnTarget.textContent = "🔄 Làm mới gợi ý"
      }
      // leave the existing panel in place on error
    } finally {
      this.setLoading(false)
    }
  }

  // Dim the panel and float a spinner while a branch switch / refresh is in
  // flight, so the wait is obvious (previously switching branches showed nothing).
  setLoading(on) {
    this.panelTarget.style.transition = "opacity .15s"
    this.panelTarget.style.opacity = on ? "0.4" : ""
    this.panelTarget.style.pointerEvents = on ? "none" : ""
    if (on) {
      if (this._spinner) return
      this.ensureSpinnerKeyframes()
      const host = this.element
      if (getComputedStyle(host).position === "static") host.style.position = "relative"
      const s = document.createElement("div")
      s.style.cssText = "position:absolute; inset:0; display:grid; place-items:center; z-index:5;"
      s.innerHTML = '<span style="width:28px; height:28px; border:3px solid var(--line); ' +
        'border-top-color:var(--primary); border-radius:50%; display:inline-block; ' +
        'animation:bh-spin .7s linear infinite;"></span>'
      host.appendChild(s)
      this._spinner = s
    } else if (this._spinner) {
      this._spinner.remove()
      this._spinner = null
    }
  }

  ensureSpinnerKeyframes() {
    if (document.getElementById("bh-spin-kf")) return
    const st = document.createElement("style")
    st.id = "bh-spin-kf"
    st.textContent = "@keyframes bh-spin{to{transform:rotate(360deg)}}"
    document.head.appendChild(st)
  }

  // Lightweight hover tooltip showing the real purchase count per cell.
  bindTooltip() {
    const cells = this.panelTarget.querySelectorAll("rect[data-count]")
    cells.forEach((cell) => {
      cell.addEventListener("mouseenter", (e) => { this.highlight(cell, true); this.showTip(e, cell) })
      cell.addEventListener("mousemove", (e) => this.moveTip(e))
      cell.addEventListener("mouseleave", () => { this.highlight(cell, false); this.hideTip() })
    })
  }

  // Outline + lift the hovered cell so it's clearly the one being read.
  highlight(cell, on) {
    cell.setAttribute("stroke", on ? "var(--ink, #2A211C)" : "transparent")
    cell.style.filter = on ? "brightness(1.06)" : ""
  }

  tip() {
    if (!this._tip) {
      this._tip = document.createElement("div")
      this._tip.style.cssText = "position:fixed;z-index:9999;pointer-events:none;background:#2A211C;color:#fff;padding:6px 10px;border-radius:8px;font-size:12px;font-weight:600;white-space:nowrap;box-shadow:0 4px 14px rgba(0,0,0,.25);opacity:0;transition:opacity .1s;"
      document.body.appendChild(this._tip)
    }
    return this._tip
  }

  showTip(e, cell) {
    const t = this.tip()
    t.textContent = `${cell.dataset.slot} · ${cell.dataset.count} lượt mua`
    t.style.opacity = "1"
    this.moveTip(e)
  }

  moveTip(e) {
    const t = this.tip()
    t.style.left = `${e.clientX + 12}px`
    t.style.top = `${e.clientY - 34}px`
  }

  hideTip() { if (this._tip) this._tip.style.opacity = "0" }

  disconnect() {
    if (this._tip) { this._tip.remove(); this._tip = null }
    if (this._spinner) { this._spinner.remove(); this._spinner = null }
  }
}
