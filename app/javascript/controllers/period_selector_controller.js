import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = {
    companyId: Number,
    baseUrl: String,
  }
  static outlets = ["chart"]

  select(event) {
    event.preventDefault()
    const period = event.currentTarget.dataset.period

    this.buttonTargets.forEach(btn => {
      if (btn.dataset.period === period) {
        btn.classList.add("active")
      } else {
        btn.classList.remove("active")
      }
    })

    const url = this.buildUrl(period)
    if (this.hasChartOutlet) {
      this.chartOutlet.reload(url)
    }
  }

  buildUrl(period) {
    const base = this.baseUrlValue
    const separator = base.includes("?") ? "&" : "?"
    return `${base}${separator}period=${period}`
  }
}
