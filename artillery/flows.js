module.exports = { loadAndWaitFlow };

async function loadAndWaitFlow(page, vuContext, events, test) {

  const {step} = test
  await step('initial-load', async () => {
    await page.goto('');
    await page.locator(".phx-connected").first().waitFor()
  });
  await step('map', async() => {
    await page.locator("img.leaflet-tile-loaded").first().waitFor();
  });
}
