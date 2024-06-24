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
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import _ from "lodash";

// Leaflet for maps
import "leaflet";
import "leaflet-rotatedmarker";
import polyline from "polyline-encoded";

let locationIcon = L.icon({
  iconUrl: "/images/icon-circle-locations-default.svg",
  iconAnchor: [15, 15],
  iconSize: [30, 30],
});

let vehicleIcon = L.icon({
  iconUrl: "/images/icon-vehicle-bordered.svg",
  iconAnchor: [20, 20],
  iconSize: [40, 40],
});

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let Hooks = {};
Hooks.Leaflet = {
  mounted() {
    const centerOfBoston = [42.3516728, -71.0718109];
    this.map = L.map(this.el).setView(centerOfBoston, 15);
    L.tileLayer("https://cdn.mbta.com/osm_tiles/{z}/{x}/{y}.png", {
      maxZoom: 18,
      minZoom: 9,
      attribution:
        '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(this.map);

    let destination = JSON.parse(this.el.dataset.destination);
    let vehicle = this.el.dataset.vehicle;

    this.destination = L.marker([destination.lat, destination.lon], {
      icon: locationIcon,
      alt: destination.alt,
      interactive: false,
      keyboard: false,
    }).addTo(this.map);

    this.map.fitBounds([destination, destination], { padding: [5, 5] });

    this.handleEvent("route", (r) => {
      let decoded = polyline.decode(r.polyline);
      let location = decoded[0];

      if (this.vehicle) {
        this.vehicle.setLatLng(location).setRotationAngle(r.bearing);
      } else {
        this.vehicle = L.marker(location, {
          icon: vehicleIcon,
          alt: vehicle,
          rotationOrigin: "center center",
          rotationAngle: r.bearing,
          interactive: false,
          keyboard: false,
        }).addTo(this.map);
      }

      if (this.polyline) {
        this.polyline.setLatLngs(decoded);
      } else {
        this.polyline = L.polyline(decoded, {
          color: "blue",
          interactive: false,
        }).addTo(this.map);
      }

      this.map.fitBounds(r.bbox, { padding: [5, 5] });
    });
    this.handleEvent("clearRoute", () => {
      if (this.vehicle) {
        this.map.removeLayer(this.vehicle);
      }
      if (this.polyline) {
        this.map.removeLayer(this.polyline);
      }
      this.vehicle = this.polyline = null;

      // recenter the map
      this.map.fitBounds([destination, destination], { padding: [5, 5] });
    });
  },
};
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
