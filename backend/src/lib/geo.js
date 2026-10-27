'use strict';

const R = 6371000;
const rad = Math.PI / 180;

function distanceM(lat1, lng1, lat2, lng2) {
  const dLat = (lat2 - lat1) * rad;
  const dLng = (lng2 - lng1) * rad;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(a)));
}

// Грубый прямоугольник вокруг точки — чтобы отсечь лишние строки ещё в SQL.
function bbox(lat, lng, radiusM) {
  const dLat = radiusM / 111_320;
  const dLng = radiusM / (111_320 * Math.max(Math.cos(lat * rad), 0.01));
  return { minLat: lat - dLat, maxLat: lat + dLat, minLng: lng - dLng, maxLng: lng + dLng };
}

module.exports = { distanceM, bbox };
