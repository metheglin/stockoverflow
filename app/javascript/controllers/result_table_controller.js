import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Navigate to company detail page on row click
  navigateToCompany(event) {
    const row = event.currentTarget
    const companyId = row.dataset.companyId
    if (companyId) {
      window.Turbo.visit(`/dashboard/companies/${companyId}`)
    }
  }
}
