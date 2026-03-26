import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "presetSelect",
    "saveDialog",
    "presetName",
    "presetDescription",
  ]

  static values = {
    presetsUrl: String,
  }

  static outlets = ["filter-builder"]

  // Load a preset's conditions into the filter builder
  loadPreset() {
    const select = this.presetSelectTarget
    const option = select.options[select.selectedIndex]

    if (!option || !option.value) return

    const conditionsRaw = option.dataset.conditions
    const displayRaw = option.dataset.display

    if (!conditionsRaw) return

    try {
      const conditions = JSON.parse(conditionsRaw)
      if (this.hasFilterBuilderOutlet) {
        this.filterBuilderOutlet.restoreConditions(conditions)
      }
    } catch (e) {
      // Silently ignore parse errors
    }
  }

  // Open the save preset modal
  openSaveModal() {
    if (this.hasSaveDialogTarget) {
      this.presetNameTarget.value = ""
      this.presetDescriptionTarget.value = ""
      this.saveDialogTarget.showModal()
    }
  }

  // Close the save preset modal
  closeSaveModal() {
    if (this.hasSaveDialogTarget) {
      this.saveDialogTarget.close()
    }
  }

  // Save the current conditions as a new preset
  async savePreset() {
    const name = this.presetNameTarget.value.trim()
    if (!name) {
      this.presetNameTarget.focus()
      return
    }

    const description = this.presetDescriptionTarget.value.trim()

    // Get conditions from filter builder
    let conditionsJson = {}
    if (this.hasFilterBuilderOutlet) {
      conditionsJson = this.filterBuilderOutlet.buildConditionsJson()
    }

    const displayJson = {
      columns: [
        "securities_code", "name", "sector_33_name",
        "revenue_yoy", "operating_income_yoy", "roe", "composite_score",
      ],
      sort_by: "composite_score",
      sort_order: "desc",
      limit: 100,
    }

    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      const response = await fetch(this.presetsUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken,
        },
        body: JSON.stringify({
          screening_preset: {
            name,
            description,
            conditions_json: JSON.stringify(conditionsJson),
            display_json: JSON.stringify(displayJson),
          },
        }),
      })

      if (response.ok) {
        const data = await response.json()
        this._addPresetOption(data)
        this.closeSaveModal()
      }
    } catch (e) {
      // Silently ignore network errors
    }
  }

  // Add a new option to the preset dropdown
  _addPresetOption(preset) {
    const select = this.presetSelectTarget
    const option = document.createElement("option")
    option.value = preset.id
    option.textContent = preset.name
    option.dataset.conditions = JSON.stringify(preset.conditions_json)
    option.dataset.display = JSON.stringify(preset.display_json)
    select.appendChild(option)
    select.value = preset.id
  }
}
