import { Controller } from "@hotwired/stimulus"

// A native <dialog> modal whose body is a lazy Turbo Frame. Trigger links point at
// the frame (data-turbo-frame) so a click loads the form, and open the dialog. The
// form inside breaks out to _top on submit, so a successful save does a full-page
// redirect back to the list; a validation error re-renders the form as a page.
export default class extends Controller {
  static targets = ["dialog", "frame"]
  // A form that failed validation re-renders the whole page, so the dialog it
  // was in has to come back open with the errors still shown.
  static values = { open: Boolean }

  connect() {
    this.loadingHTML = this.hasFrameTarget ? this.frameTarget.innerHTML : ""
    if (this.openValue) this.open()
    this.onLoad = () => this.open()
    if (this.hasFrameTarget) this.frameTarget.addEventListener("turbo:frame-load", this.onLoad)
  }

  disconnect() {
    if (this.hasFrameTarget) this.frameTarget.removeEventListener("turbo:frame-load", this.onLoad)
  }

  open() {
    if (this.hasDialogTarget && !this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
    // Reset the frame so re-opening (even the same reward) reloads a fresh form.
    if (this.hasFrameTarget) {
      this.frameTarget.removeAttribute("complete")
      this.frameTarget.removeAttribute("src")
      this.frameTarget.innerHTML = this.loadingHTML
    }
  }

  // Close when the click lands on the backdrop (the <dialog> itself, not its card).
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
