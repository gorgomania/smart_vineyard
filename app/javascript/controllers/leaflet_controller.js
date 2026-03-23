import { Controller } from "@hotwired/stimulus";
import L from 'leaflet';

export default class extends Controller {
  connect() {
    // Инициализируем карту
    this.map = L.map(this.element).setView([55.751244, 37.618423], 13);

    // Добавляем слой с картой от OpenStreetMap
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map);

    // Добавляем маркер
    L.marker([55.751244, 37.618423]).addTo(this.map)
        .bindPopup('Привет, это Москва!')
        .openPopup();
  }
}