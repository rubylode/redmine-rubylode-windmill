// README screenshots from the demo Redmine (ruby bin/demo up), in its default theme.  npm run screenshots
import { mkdirSync } from "node:fs"
import { baseUrl, launch, signedInPage, useScenario } from "./browser.mjs"

const out = new URL("../docs/screenshots/", import.meta.url).pathname
mkdirSync(out, { recursive: true })

const browser = await launch()
const page = await signedInPage(browser, "dana", "demo-password-1", { width: 1280, height: 900 })

async function shoot(name, path, selector, scenario) {
  await useScenario(scenario)
  await page.goto(`${baseUrl}${path}`, { waitUntil: "load" })
  await page.waitForSelector(selector)
  await page.mouse.move(2, 600)
  const box = await page.locator("#content").boundingBox()
  await page.screenshot({ path: `${out}${name}.png`, clip: { x: box.x - 10, y: box.y - 10, width: box.width + 20, height: Math.min(box.height + 20, 820) } })
  console.log("saved", `${name}.png`)
}

await shoot("status-failures", "/status/windmill", ".rubylode-windmill-failures", "failures")
await shoot("status-all-green", "/status/windmill", ".rubylode-windmill-status-summary.is-ok", "all_green")
await shoot("status-unavailable", "/status/windmill", ".rubylode-windmill-status-summary.is-unavailable", "unavailable")

await useScenario("failures")
const admin = await signedInPage(browser, "admin", "admin", { width: 1280, height: 900 })
await admin.goto(`${baseUrl}/settings/plugin/redmine_rubylode_windmill`, { waitUntil: "load" })
await admin.waitForSelector(".rubylode-status-notice")
const section = await admin.locator("h3", { hasText: /^Show the block on$/ }).boundingBox()
await admin.screenshot({ path: `${out}settings-where-to-show.png`, fullPage: true, clip: { x: 0, y: section.y - 20, width: 1280, height: 764 } })
console.log("saved settings-where-to-show.png")

await browser.close()
