import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    const hash = window.location.hash.replace("#", "")
    if (hash) {
      this.activate(hash)
    } else {
      this.activateFirst()
    }

    this._onPopState = () => {
      const h = window.location.hash.replace("#", "")
      if (h) this.activate(h)
    }
    window.addEventListener("popstate", this._onPopState)
  }

  disconnect() {
    window.removeEventListener("popstate", this._onPopState)
  }

  select(event) {
    event.preventDefault()
    const tabName = event.currentTarget.dataset.tab
    this.activate(tabName)
    history.pushState(null, "", `#${tabName}`)
  }

  activate(tabName) {
    this.tabTargets.forEach(tab => {
      if (tab.dataset.tab === tabName) {
        tab.classList.add("active")
      } else {
        tab.classList.remove("active")
      }
    })

    this.panelTargets.forEach(panel => {
      if (panel.dataset.tab === tabName) {
        panel.hidden = false
        this.triggerLazyLoad(panel)
      } else {
        panel.hidden = true
      }
    })
  }

  activateFirst() {
    const firstTab = this.tabTargets[0]
    if (firstTab) {
      this.activate(firstTab.dataset.tab)
    }
  }

  triggerLazyLoad(panel) {
    const frame = panel.querySelector("turbo-frame[loading='lazy']")
    if (frame && !frame.src && frame.dataset.src) {
      frame.src = frame.dataset.src
    }
  }
}
