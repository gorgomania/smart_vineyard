import { Controller } from "@hotwired/stimulus"
import "chart.js"
import { diagnosisColor } from "utils/diagnoses"

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    stats: Object  // ← принимаем JSON объект
  }

  // Вызывается при подключении и каждый раз, когда refresh-морфинг меняет data-dashboard-charts-stats-value
  statsValueChanged() {
    const stats = this.statsValue
    if (!stats || !stats.labels) return

    if (this.chart) {
      this.chart.data.labels = stats.labels
      this.chart.data.datasets[0].data = stats.data
      this.chart.data.datasets[0].backgroundColor = stats.diagnoses.map(diagnosisColor)
      this.chart.update()
    } else {
      this.renderChart(stats)
    }
  }

  // Холст data-turbo-permanent: при повторном заходе Turbo вставляет страницу с заглушкой на его месте
  // и переносит холст позже, уже после connect — поэтому рисуем, когда холст действительно появился
  canvasTargetConnected() {
    this.statsValueChanged()
  }

  canvasTargetDisconnected(canvas) {
    if (this.chart?.canvas === canvas) this.disconnect()
  }

  disconnect() {
    this.chart?.destroy()
    this.chart = null
  }

  renderChart(stats) {
    const canvas = this.canvasTargets.find(c => c.id === "total-chart")
    if (!canvas) return

    const ctx = canvas.getContext('2d')

    this.chart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: stats.labels,
        datasets: [{
          data: stats.data,
          backgroundColor: stats.diagnoses.map(diagnosisColor),
          borderWidth: 0
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false, // пропорции задаёт контейнер (aspect-square в stats.html.erb)
        plugins: {
          legend: { position: 'bottom' },
          tooltip: {
            callbacks: {
              label: (context) => {
                const total = context.dataset.data.reduce((a, b) => a + b, 0)
                const percent = ((context.raw / total) * 100).toFixed(1)
                return `${context.label}: ${context.raw} (${percent}%)`
              }
            }
          }
        }
      }
    })
  }
}
