// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
// import 'phoenix_html'
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'

// Leaflet for maps
import * as L from 'leaflet'
import 'leaflet-rotatedmarker'
import polyline from '@mapbox/polyline'

// Core Web Vitals analytics
import { onCLS, onINP, onLCP } from 'web-vitals/attribution'

// Sentry
import { replayIntegration, init as sentryInit } from '@sentry/browser'

const postBlob = (blob) => {
  const path = window.location.pathname
  const body = JSON.stringify({ ...blob, path })
  fetch('/analytics', { body, method: 'POST', keepalive: true })
}

let sendBeacon = postBlob

if (navigator.sendBeacon) {
  sendBeacon = (blob) => {
    const path = window.location.pathname
    const body = JSON.stringify({ ...blob, path })
    navigator.sendBeacon('/analytics', body)
  }
}

(() => {
/* global SENTRY_DSN */
  if (SENTRY_DSN) {
    sentryInit({
      dsn: SENTRY_DSN,
      integrations: [
        replayIntegration({
          maskAllText: false,
          blockAllMedia: false
        })
      ],
      // Session Replay
      replaysSessionSampleRate: 0.01, // This sets the sample rate at 10%. You may want to change it to 100% while in development and then sample at a lower rate in production.
      replaysOnErrorSampleRate: 1.0 // If you're not already sampling the entire session, change the sample rate to 100% when sampling sessions where errors occur.
    })
  } else {
    window.addEventListener('error', (event) => {
      const source = event.filename
      const lineno = event.lineno
      const colno = event.colno
      const name = event.error
      const message = event.message
      postBlob({ source, lineno, colno, name, message })
    })
  }
})()

function sendToAnalytics ({ name, value, id, delta, attribution }) {
  const eventParams = { name, value, id, delta }

  switch (name) {
    case 'CLS':
      eventParams.debug_target = attribution.largestShiftTarget
      break
    case 'INP':
      eventParams.debug_target = attribution.interactionTarget
      break
    case 'LCP':
      eventParams.debug_target = attribution.element
      break
  }

  sendBeacon(eventParams)
}

onCLS(sendToAnalytics)
onINP(sendToAnalytics)
onLCP(sendToAnalytics)

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')

function initializeMap (el) {
  const locationIcon = L.icon({
    iconUrl: document.getElementById('location-icon').src,
    iconAnchor: [15, 15],
    iconSize: [30, 30]
  })

  const vehicleIcon = L.icon({
    iconUrl: document.getElementById('vehicle-icon').src,
    iconAnchor: [20, 20],
    iconSize: [40, 40]
  })

  const { lat, lon, alt } = JSON.parse(el.dataset.destination)

  const destination = L.marker([lat, lon], {
    icon: locationIcon,
    alt,
    interactive: false,
    keyboard: false
  })

  const tileLayer = L.tileLayer('https://cdn.mbta.com/osm_tiles/{z}/{x}/{y}.png', {
    maxZoom: 18,
    minZoom: 9,
    attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
  })

  const map = L.map(el, {
    layers: [
      tileLayer,
      destination
    ]
  })

  let vehicleLayer, polylineLayer, popupElement

  function callback () {
    if (el.dataset.polyline) {
      const decoded = polyline.decode(el.dataset.polyline)
      const location = decoded[0]

      if (vehicleLayer) {
        vehicleLayer.setLatLng(location).setRotationAngle(parseInt(el.dataset.vehicleHeading))
        vehicleLayer.getIcon().alt = el.dataset.vehicle
      } else {
        vehicleLayer = L.marker(location, {
          icon: vehicleIcon,
          alt: el.dataset.vehicle,
          rotationOrigin: 'center center',
          rotationAngle: parseInt(el.dataset.vehicleHeading),
          interactive: false,
          keyboard: false
        }).addTo(map)
      }

      if (polylineLayer) {
        polylineLayer.setLatLngs(decoded)
      } else {
        polylineLayer = L.polyline(decoded, {
          color: 'blue',
          interactive: false
        }).addTo(map)
      }
    } else {
      if (vehicleLayer) {
        map.removeLayer(vehicleLayer)
      }
      if (polylineLayer) {
        map.removeLayer(polylineLayer)
      }
      vehicleLayer = polylineLayer = null
    }

    // fitBounds/setView needs to happen before we can show the popup. not sure why -ps
    if (el.dataset.bbox) {
      map.fitBounds(JSON.parse(el.dataset.bbox), { padding: [48, 48] })
    } else {
      map.setView(destination.getLatLng(), 17)
    }

    if (el.dataset.popup) {
      const element = document.createElement('span')
      element.innerText = el.dataset.popup
      if (popupElement) {
        popupElement.setPopupContent(element)
      } else {
        popupElement = destination.bindPopup(element, {
          offset: [0, -10],
          maxWidth: 250,
          closeButton: false,
          autoClose: false,
          closeOnEscapeKey: false,
          closeOnClick: false,
          interactive: false,
          className: 'destination-popup'
        }).openPopup()
      }
    } else {
      if (popupElement) {
        destination.closePopup()
      }
      popupElement = null
    }
    map.invalidateSize()
  }

  callback()

  /* global MutationObserver */
  const observer = new MutationObserver(callback)
  observer.observe(el, {
    attributeFilter: ['data-vehicle', 'data-vehicle-heading', 'data-bbox', 'data-polyline', 'data-popup']
  })
}

const mapEl = document.getElementById('map')
if (mapEl) {
  initializeMap(mapEl)
}

window.setTimeout(() => {
  let sessionStore, localStore

  try {
    sessionStore = window.sessionStorage
    localStore = window.localStorage
  } catch (_e) {
    class InMemoryStorage {
      constructor () { this.storage = {} }
      getItem (keyName) { return this.storage[keyName] || null }
      removeItem (keyName) { delete this.storage[keyName] }
      setItem (keyName, keyValue) { this.storage[keyName] = keyValue }
    }
    sessionStore = new InMemoryStorage()
    localStore = new InMemoryStorage()
  }

  const liveSocket = new LiveSocket('/live', Socket, {
    longPollFallbackMs: 10000,
    sessionStorage: sessionStore,
    localStorage: localStore,
    params: { _csrf_token: csrfToken }
  })

  // connect if there are any LiveViews on the page
  liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// window.liveSocket = liveSocket
}, 100)
