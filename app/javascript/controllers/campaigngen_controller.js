import { Controller } from "@hotwired/stimulus"

// "Generate with AI" button for campaign content. POSTs everything the merchant
// has already filled in (campaign name, type, audience, reward) to the server,
// fills the title + body fields with the returned suggestion, and dispatches
// input events so the live preview updates. The name matters most: it is the
// merchant's own words for what the campaign is, so never leave it out.
export default class extends Controller {
  static targets = ["title", "body", "name", "type", "audience", "reward", "button"]
  static values = { url: String }

  async generate() {
    const btn = this.hasButtonTarget ? this.buttonTarget : null
    const original = btn ? btn.textContent : null
    if (btn) { btn.disabled = true; btn.textContent = "⏳ Đang tạo…" }

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const params = new URLSearchParams()
      if (this.hasNameTarget && this.nameTarget.value.trim()) params.set("name", this.nameTarget.value.trim())
      if (this.hasTypeTarget) params.set("campaign_type", this.typeTarget.value)
      if (this.hasAudienceTarget) params.set("audience", this.audienceTarget.value)
      if (this.hasRewardTarget && this.rewardTarget.value) params.set("reward_id", this.rewardTarget.value)

      const resp = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" },
        body: params.toString()
      })
      const data = await resp.json()
      if (!resp.ok || !data.ok) {
        alert(data.error === "not_configured"
          ? "AI chưa được cấu hình (thiếu API key)."
          : "Không tạo được nội dung. Vui lòng thử lại.")
        return
      }
      if (this.hasTitleTarget && data.title) { this.titleTarget.value = data.title; this.fire(this.titleTarget) }
      if (this.hasBodyTarget && data.body)   { this.bodyTarget.value = data.body;  this.fire(this.bodyTarget) }
    } catch (e) {
      alert("Có lỗi khi gọi AI. Vui lòng thử lại.")
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = original }
    }
  }

  fire(el) { el.dispatchEvent(new Event("input", { bubbles: true })) }
}
