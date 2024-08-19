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
import polyline from 'polyline-encoded'

// Core Web Vitals analytics
import { onCLS, onINP, onLCP } from 'web-vitals'

function sendToAnalytics ({ name, value, id }) {
  const path = window.location.pathname
  const body = JSON.stringify({ path, name, value, id });
  (navigator.sendBeacon && navigator.sendBeacon('/analytics', body)) ||
      fetch('/analytics', { body, method: 'POST', keepalive: true })
}

onCLS(sendToAnalytics)
onINP(sendToAnalytics)
onLCP(sendToAnalytics)

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')

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

const Hooks = {
  Leaflet: {
    mounted () {
      const { lat, lon, alt } = JSON.parse(this.el.dataset.destination)

      this.destination = L.marker([lat, lon], {
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

      this.map = L.map(this.el, {
        layers: [
          tileLayer,
          this.destination
        ]
      })

      window.setTimeout(this.updated.bind(this), 0)
    },

    updated () {
      if (this.el.dataset.polyline) {
        const decoded = polyline.decode(this.el.dataset.polyline)
        const location = decoded[0]

        if (this.vehicle) {
          this.vehicle.setLatLng(location).setRotationAngle(parseInt(this.el.dataset.vehicleHeading))
        } else {
          this.vehicle = L.marker(location, {
            icon: vehicleIcon,
            alt: this.el.dataset.vehicle,
            rotationOrigin: 'center center',
            rotationAngle: parseInt(this.el.dataset.vehicleHeading),
            interactive: false,
            keyboard: false
          }).addTo(this.map)
        }

        if (this.polyline) {
          this.polyline.setLatLngs(decoded)
        } else {
          this.polyline = L.polyline(decoded, {
            color: 'blue',
            interactive: false
          }).addTo(this.map)
        }
      } else {
        if (this.vehicle) {
          this.map.removeLayer(this.vehicle)
        }
        if (this.polyline) {
          this.map.removeLayer(this.polyline)
        }
        this.vehicle = this.polyline = null
      }

      // fitBounds/setView needs to happen before we can show the popup. not sure why -ps
      if (this.el.dataset.bbox) {
        this.map.fitBounds(JSON.parse(this.el.dataset.bbox), { padding: [48, 48] })
      } else {
        this.map.setView(this.destination.getLatLng(), 15)
      }

      if (this.el.dataset.popup) {
        const element = document.createElement('span')
        element.innerText = this.el.dataset.popup
        if (this.popup) {
          this.popup.setPopupContent(element)
        } else {
          this.popup = this.destination.bindPopup(element, {
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
        if (this.popup) {
          this.destination.closePopup()
        }
        this.popup = null
      }
    }
  }
}

const liveSocket = new LiveSocket('/live', Socket, {
  longPollFallbackMs: 10000,
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// window.liveSocket = liveSocket
