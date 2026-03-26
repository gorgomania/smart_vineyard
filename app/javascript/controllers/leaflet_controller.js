import { Controller } from "@hotwired/stimulus";
import L from 'leaflet';

export default class extends Controller {
  connect() {
    // Координаты Севастополя
    const sevastopolLat = 44.5945;
    const sevastopolLng = 33.477;
    
    // Инициализируем карту с центром в Севастополе
    this.map = L.map(this.element, {attributionControl: false}).setView([sevastopolLat, sevastopolLng], 13);

    // Добавляем слой с картой от OpenStreetMap
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map);

    const myAttrControl = L.control.attribution({ prefix: '<a href="https://leafletjs.com/">Leaflet</a>' });
    myAttrControl.addTo(this.map);

    // Добавляем маркер в Севастополе
    L.marker([sevastopolLat, sevastopolLng]).addTo(this.map)
        .bindPopup('Привет, это СевГУ!')
        .openPopup();
  }
}