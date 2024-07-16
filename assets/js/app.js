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
import topbar from '../vendor/topbar'

// Leaflet for maps
import * as L from 'leaflet'
import 'leaflet-rotatedmarker'
import polyline from 'polyline-encoded'

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')
const Hooks = {}
Hooks.Leaflet = {
  mounted () {
    const centerOfBoston = [42.3516728, -71.0718109]
    const locationIcon = L.icon({
      iconUrl: this.el.dataset.locationIcon,
      iconAnchor: [15, 15],
      iconSize: [30, 30]
    })

    const vehicleIcon = L.icon({
      iconUrl: this.el.dataset.vehicleIcon,
      iconAnchor: [20, 20],
      iconSize: [40, 40]
    })

    this.map = L.map(this.el).setView(centerOfBoston, 15)
    L.tileLayer('https://cdn.mbta.com/osm_tiles/{z}/{x}/{y}.png', {
      maxZoom: 18,
      minZoom: 9,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(this.map)

    const destination = JSON.parse(this.el.dataset.destination)
    const vehicle = this.el.dataset.vehicle

    this.destination = L.marker([destination.lat, destination.lon], {
      icon: locationIcon,
      alt: destination.alt,
      interactive: false,
      keyboard: false
    }).addTo(this.map)

    this.map.fitBounds([destination, destination], { padding: [5, 5] })

    this.handleEvent('route', (r) => {
      const decoded = polyline.decode(r.polyline)
      const location = decoded[0]

      if (this.vehicle) {
        this.vehicle.setLatLng(location).setRotationAngle(r.bearing)
      } else {
        this.vehicle = L.marker(location, {
          icon: vehicleIcon,
          alt: vehicle,
          rotationOrigin: 'center center',
          rotationAngle: r.bearing,
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

      this.map.fitBounds(r.bbox, { padding: [5, 5] })
    })
    this.handleEvent('clearRoute', (d) => {
      if (this.vehicle) {
        this.map.removeLayer(this.vehicle)
      }
      if (this.polyline) {
        this.map.removeLayer(this.polyline)
      }
      this.vehicle = this.polyline = null

      // recenter the map
      this.map.fitBounds([destination, destination], { padding: [5, 5] })
      this.destination.closePopup()
      if (d.popup) {
        this.destination.bindPopup(d.popup, {
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
    })
  }
}
const liveSocket = new LiveSocket('/live', Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' })
window.addEventListener('phx:page-loading-start', (_info) => topbar.show(300))
window.addEventListener('phx:page-loading-stop', (_info) => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
