import { Controller } from "@hotwired/stimulus"
import "chart.js"

export default class extends Controller {
  static targets = ["canvas"]
  
  async connect() {
    await this.loadData()
  }
  
  async loadData() {
    const response = await fetch('/vineyards/statistics', {
      headers: { 'Accept': 'application/json' }
    })
    this.vineyardsData = await response.json()
    
    this.renderTotalCharts()
    this.renderQuickStats()
    this.renderVineyardCharts()
  }
  
  renderTotalCharts() {
    const totalHealthy = this.vineyardsData.reduce((sum, v) => sum + v.healthy, 0)
    const totalSick = this.vineyardsData.reduce((sum, v) => sum + v.sick, 0)
    const totalNoData = this.vineyardsData.reduce((sum, v) => sum + v.no_data, 0)
    
    const ctx = this.canvasTargets.find(c => c.id === "total-chart").getContext('2d')
    
    new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: ['Здоровые', 'Больные', 'Нет данных'],
        datasets: [{
          data: [totalHealthy, totalSick, totalNoData],
          backgroundColor: ['#22C55E', '#EF4444', '#9CA3AF'],
          borderWidth: 0
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { position: 'bottom' }
        }
      }
    })
  }
  
  renderQuickStats() {
    const container = document.getElementById('quick-stats')
    const totalVineyards = this.vineyardsData.length
    const totalBushes = this.vineyardsData.reduce((sum, v) => sum + v.total, 0)
    const totalAnalyzed = this.vineyardsData.reduce((sum, v) => sum + (v.total - v.no_data), 0)
    
    container.innerHTML = `
      <div class="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
        <span>🍇 Виноградников:</span>
        <span class="font-bold text-[#69377c]">${totalVineyards}</span>
      </div>
      <div class="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
        <span>🌿 Всего кустов:</span>
        <span class="font-bold text-[#69377c]">${totalBushes}</span>
      </div>
      <div class="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
        <span>🔬 Проанализировано:</span>
        <span class="font-bold text-[#69377c]">${totalAnalyzed}</span>
      </div>
      <div class="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
        <span>📸 Процент анализа:</span>
        <span class="font-bold text-[#69377c]">${Math.round(totalAnalyzed / totalBushes * 100)}%</span>
      </div>
    `
  }
  
  renderVineyardCharts() {
    const container = document.getElementById('vineyards-charts')
    
    container.innerHTML = this.vineyardsData.map(vineyard => `
      <div class="bg-white rounded-xl shadow-sm p-4">
        <h3 class="font-bold text-[#69377c] mb-2">${vineyard.name}</h3>
        <div class="text-sm text-gray-600 mb-3">
          🌿 Кустов: ${vineyard.total} | 📸 Анализ: ${Math.round((vineyard.total - vineyard.no_data) / vineyard.total * 100)}%
        </div>
        <canvas id="chart-${vineyard.id}" class="w-full h-48"></canvas>
        <div class="mt-3 text-center">
          <a href="/vineyards/${vineyard.id}" class="text-sm text-purple-600 hover:underline">Подробнее →</a>
        </div>
      </div>
    `).join('')
    
    // Рендерим диаграммы для каждого виноградника
    this.vineyardsData.forEach(vineyard => {
      const canvas = document.getElementById(`chart-${vineyard.id}`)
      if (canvas) {
        const ctx = canvas.getContext('2d')
        new Chart(ctx, {
          type: 'pie',
          data: {
            labels: vineyard.labels,
            datasets: [{
              data: vineyard.data,
              backgroundColor: vineyard.colors,
              borderWidth: 0
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
              legend: { position: 'bottom', labels: { font: { size: 10 } } }
            }
          }
        })
      }
    })
  }
}