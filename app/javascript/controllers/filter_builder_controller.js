import { Controller } from "@hotwired/stimulus"

// Field definitions for each condition type
const FIELD_OPTIONS = {
  metric_range: [
    ["売上高成長率(YoY)", "revenue_yoy"],
    ["営業利益成長率(YoY)", "operating_income_yoy"],
    ["経常利益成長率(YoY)", "ordinary_income_yoy"],
    ["純利益成長率(YoY)", "net_income_yoy"],
    ["EPS成長率(YoY)", "eps_yoy"],
    ["ROE(自己資本利益率)", "roe"],
    ["ROA(総資産利益率)", "roa"],
    ["営業利益率", "operating_margin"],
    ["経常利益率", "ordinary_margin"],
    ["純利益率", "net_margin"],
    ["フリーキャッシュフロー", "free_cf"],
    ["連続増収期数", "consecutive_revenue_growth"],
    ["連続増益期数", "consecutive_profit_growth"],
  ],
  data_json_range: [
    ["PER(株価収益率)", "per"],
    ["PBR(株価純資産倍率)", "pbr"],
    ["PSR(株価売上高倍率)", "psr"],
    ["配当利回り", "dividend_yield"],
    ["EV/EBITDA", "ev_ebitda"],
    ["流動比率", "current_ratio"],
    ["D/Eレシオ", "debt_to_equity"],
    ["ネットD/Eレシオ", "net_debt_to_equity"],
    ["総資産回転率", "asset_turnover"],
    ["売上総利益率", "gross_margin"],
    ["販管費率", "sga_ratio"],
    ["成長スコア", "growth_score"],
    ["品質スコア", "quality_score"],
    ["バリュースコア", "value_score"],
    ["総合スコア", "composite_score"],
    ["売上高CAGR(3年)", "revenue_cagr_3y"],
    ["売上高CAGR(5年)", "revenue_cagr_5y"],
    ["営業利益CAGR(3年)", "operating_income_cagr_3y"],
    ["営業利益CAGR(5年)", "operating_income_cagr_5y"],
    ["純利益CAGR(3年)", "net_income_cagr_3y"],
    ["純利益CAGR(5年)", "net_income_cagr_5y"],
    ["EPS CAGR(3年)", "eps_cagr_3y"],
    ["EPS CAGR(5年)", "eps_cagr_5y"],
    ["配当性向", "payout_ratio"],
    ["配当成長率", "dividend_growth_rate"],
    ["連続増配期数", "consecutive_dividend_growth"],
    ["売上高成長加速度", "revenue_growth_acceleration"],
    ["営業利益成長加速度", "operating_income_growth_acceleration"],
    ["純利益成長加速度", "net_income_growth_acceleration"],
    ["EPS成長加速度", "eps_growth_acceleration"],
  ],
  metric_boolean: [
    ["営業CF正", "operating_cf_positive"],
    ["投資CF負", "investing_cf_negative"],
    ["FCF正", "free_cf_positive"],
  ],
  company_attribute: [
    ["セクター(17分類)", "sector_17_code"],
    ["セクター(33分類)", "sector_33_code"],
    ["市場区分", "market_code"],
    ["規模区分", "scale_category"],
  ],
  trend_filter: [
    ["売上高トレンド", "trend_revenue"],
    ["営業利益トレンド", "trend_operating_income"],
    ["純利益トレンド", "trend_net_income"],
    ["EPSトレンド", "trend_eps"],
    ["営業利益率トレンド", "trend_operating_margin"],
    ["ROEトレンド", "trend_roe"],
    ["ROAトレンド", "trend_roa"],
    ["フリーCFトレンド", "trend_free_cf"],
  ],
  temporal: [
    ["ROE(自己資本利益率)", "roe"],
    ["ROA(総資産利益率)", "roa"],
    ["営業利益率", "operating_margin"],
    ["純利益率", "net_margin"],
    ["売上高成長率(YoY)", "revenue_yoy"],
    ["営業利益成長率(YoY)", "operating_income_yoy"],
    ["純利益成長率(YoY)", "net_income_yoy"],
    ["EPS成長率(YoY)", "eps_yoy"],
    ["FCF正", "free_cf_positive"],
    ["営業CF正", "operating_cf_positive"],
  ],
}

const TEMPORAL_TYPE_OPTIONS = [
  ["N期中M期達成", "at_least_n_of_m"],
  ["N期連続改善", "improving"],
  ["N期連続悪化", "deteriorating"],
  ["プラス転換", "transition_positive"],
  ["マイナス転換", "transition_negative"],
]

const TEMPORAL_BOOLEAN_FIELDS = ["free_cf_positive", "operating_cf_positive"]

export default class extends Controller {
  static targets = [
    "container",
    "conditionRows",
    "conditionTemplate",
    "conditionRow",
    "logicSelect",
    "searchButton",
    "status",
  ]

  static values = {
    executeUrl: String,
  }

  connect() {
    // Add an initial empty condition row on connect
    if (this.conditionRowTargets.length === 0) {
      this.addCondition()
    }
  }

  // Add a new condition row from template
  addCondition() {
    const template = this.conditionTemplateTarget
    const clone = template.content.cloneNode(true)
    this.conditionRowsTarget.appendChild(clone)
  }

  // Remove a condition row
  removeCondition(event) {
    const row = event.target.closest("[data-filter-builder-target='conditionRow']")
    if (row) {
      row.remove()
    }
  }

  // When condition type changes, update field options and show appropriate value inputs
  changeConditionType(event) {
    const row = event.target.closest("[data-filter-builder-target='conditionRow']")
    const conditionType = event.target.value
    const fieldSelect = row.querySelector(".condition-field-select")

    // Reset and populate field select
    fieldSelect.innerHTML = '<option value="">-- 指標を選択 --</option>'
    const options = FIELD_OPTIONS[conditionType] || []
    options.forEach(([label, value]) => {
      const opt = document.createElement("option")
      opt.value = value
      opt.textContent = label
      fieldSelect.appendChild(opt)
    })
    fieldSelect.style.display = conditionType ? "" : "none"

    // Show/hide value input groups based on type
    this._toggleValueInputs(row, conditionType)
  }

  // When field changes, update temporal UI if applicable
  changeField(event) {
    const row = event.target.closest("[data-filter-builder-target='conditionRow']")
    const conditionType = row.querySelector(".condition-type-select")?.value
    if (conditionType === "temporal") {
      this._updateTemporalInputVisibility(row)
    }
  }

  // When temporal type changes, update visible sub-inputs
  changeTemporalType(event) {
    const row = event.target.closest("[data-filter-builder-target='conditionRow']")
    this._updateTemporalInputVisibility(row)
  }

  // Reset all conditions
  resetAll() {
    this.conditionRowsTarget.innerHTML = ""
    this.logicSelectTarget.value = "and"
    this.addCondition()

    // Clear results
    const resultsFrame = document.getElementById("search_results")
    if (resultsFrame) {
      resultsFrame.innerHTML = `
        <div class="section-card results-placeholder">
          <p class="text-secondary text-center">条件を指定して「検索実行」をクリックしてください</p>
        </div>`
    }
    this._updateStatus("")
  }

  // Build conditions JSON from the current DOM state
  buildConditionsJson() {
    const logic = this.logicSelectTarget.value
    const conditions = []

    this.conditionRowTargets.forEach((row) => {
      const condition = this._parseConditionRow(row)
      if (condition) {
        conditions.push(condition)
      }
    })

    return { logic, conditions }
  }

  // Execute search via Turbo Stream
  async executeSearch() {
    const conditionsJson = this.buildConditionsJson()

    if (conditionsJson.conditions.length === 0) {
      this._updateStatus("条件を1つ以上指定してください")
      return
    }

    this.searchButtonTarget.disabled = true
    this._updateStatus("検索中...")

    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      const response = await fetch(this.executeUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrfToken,
        },
        body: this._buildFormBody(conditionsJson),
      })

      if (response.ok) {
        const html = await response.text()
        window.Turbo.renderStreamMessage(html)
        this._updateStatus("")
      } else {
        this._updateStatus("検索に失敗しました")
      }
    } catch (error) {
      this._updateStatus("通信エラーが発生しました")
    } finally {
      this.searchButtonTarget.disabled = false
    }
  }

  // Restore conditions from a preset's data (called by preset_manager_controller)
  restoreConditions(conditionsData) {
    this.conditionRowsTarget.innerHTML = ""

    if (conditionsData.logic) {
      this.logicSelectTarget.value = conditionsData.logic
    }

    const conditions = conditionsData.conditions || []
    if (conditions.length === 0) {
      this.addCondition()
      return
    }

    conditions.forEach((condition) => {
      this.addCondition()
      const row = this.conditionRowTargets[this.conditionRowTargets.length - 1]
      this._restoreConditionRow(row, condition)
    })
  }

  // --- Private methods ---

  _parseConditionRow(row) {
    const typeSelect = row.querySelector(".condition-type-select")
    const fieldSelect = row.querySelector(".condition-field-select")
    const conditionType = typeSelect?.value
    const field = fieldSelect?.value

    if (!conditionType || !field) return null

    switch (conditionType) {
      case "metric_range":
      case "data_json_range": {
        const min = row.querySelector(".condition-min")?.value
        const max = row.querySelector(".condition-max")?.value
        if (!min && !max) return null
        const condition = { type: conditionType, field }
        if (min) condition.min = parseFloat(min)
        if (max) condition.max = parseFloat(max)
        return condition
      }
      case "metric_boolean": {
        const value = row.querySelector(".condition-boolean-value")?.value
        return { type: conditionType, field, value: value === "true" }
      }
      case "company_attribute": {
        const rawValue = row.querySelector(".condition-attribute-value")?.value || ""
        const values = rawValue.split(",").map((v) => v.trim()).filter((v) => v)
        if (values.length === 0) return null
        return { type: conditionType, field, values }
      }
      case "trend_filter": {
        const trendValue = row.querySelector(".condition-trend-value")?.value
        if (!trendValue) return null
        return { type: conditionType, field, value: trendValue }
      }
      case "temporal": {
        const temporalType = row.querySelector(".condition-temporal-type")?.value
        if (!temporalType) return null
        const condition = { type: "temporal", temporal_type: temporalType, field }

        if (temporalType === "at_least_n_of_m") {
          const threshold = row.querySelector(".condition-temporal-threshold")?.value
          const comparison = row.querySelector(".condition-temporal-comparison")?.value
          const n = row.querySelector(".condition-temporal-n")?.value
          const m = row.querySelector(".condition-temporal-m")?.value
          if (!n || !m) return null
          condition.threshold = parseFloat(threshold || "0")
          condition.comparison = comparison || "gte"
          condition.n = parseInt(n, 10)
          condition.m = parseInt(m, 10)
        } else if (temporalType === "improving" || temporalType === "deteriorating") {
          const n = row.querySelector(".condition-temporal-n")?.value
          if (!n) return null
          condition.n = parseInt(n, 10)
        }
        // transition_positive / transition_negative require no extra params
        return condition
      }
      default:
        return null
    }
  }

  _toggleValueInputs(row, conditionType) {
    const rangeInputs = row.querySelector(".condition-range-inputs")
    const booleanInputs = row.querySelector(".condition-boolean-inputs")
    const attributeInputs = row.querySelector(".condition-attribute-inputs")
    const trendInputs = row.querySelector(".condition-trend-inputs")
    const temporalInputs = row.querySelector(".condition-temporal-inputs")

    // Hide all
    rangeInputs.style.display = "none"
    booleanInputs.style.display = "none"
    attributeInputs.style.display = "none"
    if (trendInputs) trendInputs.style.display = "none"
    if (temporalInputs) temporalInputs.style.display = "none"

    // Show relevant
    switch (conditionType) {
      case "metric_range":
      case "data_json_range":
        rangeInputs.style.display = ""
        break
      case "metric_boolean":
        booleanInputs.style.display = ""
        break
      case "company_attribute":
        attributeInputs.style.display = ""
        break
      case "trend_filter":
        if (trendInputs) trendInputs.style.display = ""
        break
      case "temporal":
        if (temporalInputs) temporalInputs.style.display = ""
        break
    }
  }

  // Update visibility of temporal sub-inputs based on temporal_type and field selection
  _updateTemporalInputVisibility(row) {
    const temporalType = row.querySelector(".condition-temporal-type")?.value
    const field = row.querySelector(".condition-field-select")?.value
    const isBooleanField = TEMPORAL_BOOLEAN_FIELDS.includes(field)

    const thresholdGroup = row.querySelector(".temporal-threshold-group")
    const nGroup = row.querySelector(".temporal-n-group")
    const mGroup = row.querySelector(".temporal-m-group")

    if (thresholdGroup) thresholdGroup.style.display = "none"
    if (nGroup) nGroup.style.display = "none"
    if (mGroup) mGroup.style.display = "none"

    if (temporalType === "at_least_n_of_m" && !isBooleanField) {
      if (thresholdGroup) thresholdGroup.style.display = ""
      if (nGroup) nGroup.style.display = ""
      if (mGroup) mGroup.style.display = ""
    } else if (temporalType === "improving" || temporalType === "deteriorating") {
      if (nGroup) nGroup.style.display = ""
    }
    // transition_positive / transition_negative need no extra inputs
  }

  _restoreConditionRow(row, condition) {
    const typeSelect = row.querySelector(".condition-type-select")
    const fieldSelect = row.querySelector(".condition-field-select")

    // Set type
    typeSelect.value = condition.type
    typeSelect.dispatchEvent(new Event("change"))

    // Set field (need to wait for options to be populated)
    setTimeout(() => {
      fieldSelect.value = condition.field

      switch (condition.type) {
        case "metric_range":
        case "data_json_range":
          if (condition.min !== undefined) {
            row.querySelector(".condition-min").value = condition.min
          }
          if (condition.max !== undefined) {
            row.querySelector(".condition-max").value = condition.max
          }
          break
        case "metric_boolean":
          row.querySelector(".condition-boolean-value").value = String(condition.value)
          break
        case "company_attribute":
          row.querySelector(".condition-attribute-value").value =
            (condition.values || []).join(", ")
          break
        case "trend_filter":
          if (condition.value) {
            row.querySelector(".condition-trend-value").value = condition.value
          }
          break
        case "temporal":
          if (condition.temporal_type) {
            const temporalTypeSelect = row.querySelector(".condition-temporal-type")
            if (temporalTypeSelect) {
              temporalTypeSelect.value = condition.temporal_type
              temporalTypeSelect.dispatchEvent(new Event("change"))
            }
          }
          setTimeout(() => {
            if (condition.threshold !== undefined) {
              const el = row.querySelector(".condition-temporal-threshold")
              if (el) el.value = condition.threshold
            }
            if (condition.comparison) {
              const el = row.querySelector(".condition-temporal-comparison")
              if (el) el.value = condition.comparison
            }
            if (condition.n !== undefined) {
              const el = row.querySelector(".condition-temporal-n")
              if (el) el.value = condition.n
            }
            if (condition.m !== undefined) {
              const el = row.querySelector(".condition-temporal-m")
              if (el) el.value = condition.m
            }
            this._updateTemporalInputVisibility(row)
          }, 0)
          break
      }
    }, 0)
  }

  _buildFormBody(conditionsJson) {
    const params = new URLSearchParams()
    params.set("conditions_json", JSON.stringify(conditionsJson))
    params.set("display_json", JSON.stringify({
      columns: [
        "securities_code", "name", "sector_33_name",
        "revenue_yoy", "operating_income_yoy", "roe", "composite_score",
      ],
      sort_by: "composite_score",
      sort_order: "desc",
      limit: 100,
    }))
    return params.toString()
  }

  _updateStatus(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
    }
  }
}
