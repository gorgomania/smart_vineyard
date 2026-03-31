// app/javascript/maps/yandex_map.js
export function initYandexMap(containerId, center, zoom, options = {}) {
  return new Promise((resolve) => {
    ymaps.ready(() => {
      const map = new ymaps.Map(containerId, {
        center: center,
        zoom: zoom,
        controls: options.controls || ['zoomControl', 'fullscreenControl']
      });
      
      resolve(map);
    });
  });
}

export function addPlacemark(map, coordinates, properties = {}, options = {}) {
  const placemark = new ymaps.Placemark(coordinates, properties, options);
  map.geoObjects.add(placemark);
  return placemark;
}