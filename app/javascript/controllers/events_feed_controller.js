import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hidden"]

  showAll() {
    this.hiddenTargets.forEach(el => {
      el.style.display = ""
      el.classList.remove("event-item--hidden")
    })
    // Hide the "more" button
    const btn = this.element.querySelector(".events-feed__more")
    if (btn) btn.style.display = "none"
  }
}
