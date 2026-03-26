import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static values = {
    url: String,
    type: { type: String, default: "line" },
  }

  connect() {
    this.loadChart()
    this._onThemeChanged = () => this.updateColors()
    document.addEventListener("theme:changed", this._onThemeChanged)
  }

  disconnect() {
    document.removeEventListener("theme:changed", this._onThemeChanged)
    if (this.chart) this.chart.destroy()
  }

  async loadChart() {
    const response = await fetch(this.urlValue)
    const data = await response.json()
    this.renderChart(data)
  }

  renderChart(data) {
    if (this.chart) this.chart.destroy()

    const canvas = this.element.querySelector("canvas")
    if (!canvas) return
    const ctx = canvas.getContext("2d")
    const colors = this.getThemeColors()

    const datasets = (data.datasets || []).map((ds, i) => {
      const color = colors.colors[i % colors.colors.length]
      const base = {
        ...ds,
        borderColor: color,
        backgroundColor: ds.type === "bar" ? color + "99" : color + "22",
        pointBackgroundColor: color,
        borderWidth: ds.type === "bar" ? 1 : 2,
        pointRadius: ds.type === "bar" ? 0 : 2,
        tension: 0.3,
        fill: ds.type !== "bar" && ds.type !== "line",
      }

      if (ds.type === "bar") {
        base.borderColor = color
        base.backgroundColor = color + "cc"
      }

      return base
    })

    const chartType = this.hasTypeValue ? this.typeValue : "line"
    const hasMixed = datasets.some(ds => ds.type)

    this.chart = new Chart(ctx, {
      type: hasMixed ? "bar" : chartType,
      data: {
        labels: data.labels || [],
        datasets: datasets,
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          mode: "index",
          intersect: false,
        },
        plugins: {
          legend: {
            position: "bottom",
            labels: {
              color: colors.text,
              padding: 16,
              usePointStyle: true,
              pointStyle: "circle",
              font: { size: 11 },
            },
          },
          tooltip: {
            backgroundColor: "rgba(0,0,0,0.8)",
            titleFont: { size: 12 },
            bodyFont: { size: 11 },
            padding: 10,
            cornerRadius: 6,
            callbacks: {
              label: (context) => {
                const label = context.dataset.label || ""
                const value = context.parsed.y
                if (value === null || value === undefined) return null
                return `${label}: ${this.formatValue(value)}`
              },
            },
          },
        },
        scales: {
          x: {
            grid: { color: colors.grid },
            ticks: { color: colors.text, font: { size: 11 } },
          },
          y: {
            grid: { color: colors.grid },
            ticks: {
              color: colors.text,
              font: { size: 11 },
              callback: (value) => this.formatValue(value),
            },
          },
        },
      },
    })
  }

  getThemeColors() {
    const style = getComputedStyle(document.documentElement)
    return {
      colors: [
        style.getPropertyValue("--chart-color-1").trim(),
        style.getPropertyValue("--chart-color-2").trim(),
        style.getPropertyValue("--chart-color-3").trim(),
        style.getPropertyValue("--chart-color-4").trim(),
        style.getPropertyValue("--chart-color-5").trim(),
        style.getPropertyValue("--chart-color-6").trim(),
      ],
      grid: style.getPropertyValue("--chart-grid").trim(),
      text: style.getPropertyValue("--chart-text").trim(),
    }
  }

  updateColors() {
    if (!this.chart) return
    const colors = this.getThemeColors()

    this.chart.data.datasets.forEach((ds, i) => {
      const color = colors.colors[i % colors.colors.length]
      ds.borderColor = color
      ds.backgroundColor = ds.type === "bar" ? color + "cc" : color + "22"
      ds.pointBackgroundColor = color
    })

    this.chart.options.scales.x.grid.color = colors.grid
    this.chart.options.scales.x.ticks.color = colors.text
    this.chart.options.scales.y.grid.color = colors.grid
    this.chart.options.scales.y.ticks.color = colors.text
    this.chart.options.plugins.legend.labels.color = colors.text

    this.chart.update("none")
  }

  formatValue(value) {
    if (value === null || value === undefined) return "-"
    const abs = Math.abs(value)
    if (abs >= 1_000_000_000_000) return (value / 1_000_000_000_000).toFixed(2) + "兆"
    if (abs >= 100_000_000) return (value / 100_000_000).toFixed(1) + "億"
    if (abs >= 10_000) return (value / 10_000).toFixed(0) + "万"
    if (abs < 1 && abs > 0) return (value * 100).toFixed(1) + "%"
    return value.toLocaleString()
  }

  async reload(url) {
    if (url) this.urlValue = url
    await this.loadChart()
  }
}
