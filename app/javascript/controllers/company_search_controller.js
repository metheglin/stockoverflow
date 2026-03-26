import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "loading"]
  static values = { url: String }

  connect() {
    this._debounceTimer = null
  }

  disconnect() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer)
  }

  search() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer)

    this._debounceTimer = setTimeout(() => {
      this.performSearch()
    }, 300)
  }

  submit(event) {
    event.preventDefault()
    if (this._debounceTimer) clearTimeout(this._debounceTimer)
    this.performSearch()
  }

  performSearch() {
    const query = this.inputTarget.value.trim()
    const frame = document.getElementById("company_list")
    if (!frame) return

    if (this.hasLoadingTarget) this.loadingTarget.hidden = false

    const url = new URL(this.urlValue, window.location.origin)
    if (query) url.searchParams.set("q", query)

    frame.src = url.toString()

    frame.addEventListener("turbo:frame-load", () => {
      if (this.hasLoadingTarget) this.loadingTarget.hidden = true
    }, { once: true })
  }
}
