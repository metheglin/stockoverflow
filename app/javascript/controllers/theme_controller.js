import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]

  connect() {
    const saved = localStorage.getItem("theme")
    if (saved === "light") {
      document.documentElement.setAttribute("data-theme", "light")
    }
    this.updateIcon()
  }

  toggle() {
    const current = document.documentElement.getAttribute("data-theme")
    if (current === "light") {
      document.documentElement.removeAttribute("data-theme")
      localStorage.removeItem("theme")
    } else {
      document.documentElement.setAttribute("data-theme", "light")
      localStorage.setItem("theme", "light")
    }
    this.updateIcon()
    document.dispatchEvent(new CustomEvent("theme:changed"))
  }

  updateIcon() {
    if (!this.hasIconTarget) return

    const isLight = document.documentElement.getAttribute("data-theme") === "light"
    // Sun icon for dark mode (click to switch to light), Moon icon for light mode (click to switch to dark)
    if (isLight) {
      this.iconTarget.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path>
        </svg>`
    } else {
      this.iconTarget.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="5"></circle>
          <line x1="12" y1="1" x2="12" y2="3"></line>
          <line x1="12" y1="21" x2="12" y2="23"></line>
          <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line>
          <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line>
          <line x1="1" y1="12" x2="3" y2="12"></line>
          <line x1="21" y1="12" x2="23" y2="12"></line>
          <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line>
          <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line>
        </svg>`
    }
  }
}
