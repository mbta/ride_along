// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const { colors: defaultColors } = require('tailwindcss/defaultTheme')
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/ride_along_web.ex",
    "../lib/ride_along_web/**/*.*ex"
  ],
  theme: {
    fontFamily: {
      "inter-thin": ["InterThin"],
      "inter-extralight": ["InterExtraLight"],
      "inter-light": ["InterLight"],
      "inter-normal": ["InterNormal"],
      "inter-medium": ["InterMedium"],
      "inter-semibold": ["InterSemiBold"],
      "inter-bold": ["InterBold"],
      "inter-extrabold": ["InterExtraBold"],
      "inter-black": ["InterBlack"],
      helvetica: ["Helvetica Neue", "system-ui", "sans-serif"],
      sans: ["InterNormal", "system-ui", "sans-serif"],
    },
    extend: {
      colors: {
        ...defaultColors,
        "mbta-blue": "#003DA5",
        "mbta-green": "#00843D",
        "mbta-red": "#DA291C",
        "mbta-orange": "#ED8B00",
        "mbta-silver": "#7C878E",
        "mbta-purple": "#80276C",
        "mbta-bus": "#FFC72C",
        "mbta-ferry": "#008EAA",
        "mbta-ride": "#59BEC9",
        "mbta-swa": "#00B5E2",
        "mbta-gray-dark": "#212322",
        "mbta-winter-blue": "#13294B",
        "mbta-midwinter-blue": "#147BD1",
        "light-silver": "#D9D9D9",
        blue: {
          300: "#A1C6ED",
          500: "#165C96",
          600: "#092E4D",
        },
        red: {
          500: "#F2DEDE",
          600: "#B3000F",
        },
        yellow: {
          500: "#E59700",
        },
        gray: {
          200: "#E9EAED"
        },
        "callout-light-blue": "#CFE2FF",
        "callout-light-yellow": "#FFF7BF",
        "callout-light-green": "#DFF0D8",
        "callout-light-red": "#F2DEDE",
        "callout-outline-blue": "#B6D4FE",
        "callout-outline-yellow": "#FFDD00",
        "callout-outline-green": "#BADBCC",
        "callout-outline-red": "#B3000F",
        "callout-dark-blue": "#084298",
        "callout-dark-green": "#145A06",
        "callout-dark-red": "#B3000F",
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}
