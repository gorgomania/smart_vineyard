import { Controller } from "@hotwired/stimulus"
import "chart.js"

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    stats: Object  // ← принимаем JSON объект
  }
  
  connect() {
    this.renderChart()
  }
  
  renderChart() {
    const stats = this.statsValue
    
    if (!stats || !stats.labels) return
    
    const canvas = this.canvasTargets.find(c => c.id === "total-chart")
    if (!canvas) return
    
    const ctx = canvas.getContext('2d')
    
    new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: stats.labels,
        datasets: [{
          data: stats.data,
          backgroundColor: stats.colors,
          borderWidth: 0
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        plugins: {
          legend: { position: 'bottom' },
          tooltip: {
            callbacks: {
              label: (context) => {
                const total = stats.data.reduce((a, b) => a + b, 0)
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