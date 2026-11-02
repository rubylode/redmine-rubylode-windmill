// Checks the block in the running demo, scenario by scenario, as the administrator and as a plain user.  npm run check
import { baseUrl, launch, signedInPage, anonymousPage, useScenario } from "./browser.mjs"

const browser = await launch()
let failures = 0
const expect = (description, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures += 1
  console.log(`${ok ? "ok  " : "FAIL"} ${description}${ok ? "" : ` (got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)})`}`)
}
const text = async (page, selector) => (await page.locator(selector).allInnerTexts()).map((value) => value.replace(/\s+/g, " ").trim())
const open = async (page, path) => page.goto(`${baseUrl}${path}`, { waitUntil: "load" })

const dana = await signedInPage(browser, "dana", "demo-password-1")

await useScenario("failures")
await open(dana, "/windmill_status")
expect("failures: the summary counts the failing paths and late schedules", await text(dana, ".rubylode-windmill-status-summary"), ["4 failing, 2 schedules need a look"])
const failingPaths = (await text(dana, "table.rubylode-windmill-failures td.rubylode-windmill-status-path")).map((value) => value.replace(/ ×\d+$/, "")).sort()
expect("failures: the failing paths are listed", failingPaths, ["f/billing/sync_invoices", "f/crm/import_contacts", "f/reports/hourly_metrics", "f/reports/monthly_report"])
expect("failures: a recovered failure (cleanup_files) is not listed", (await text(dana, "td.rubylode-windmill-status-path")).some((value) => value.includes("cleanup_files")), false)
expect("failures: the late heartbeat is flagged", await text(dana, "tr.is-overdue td.rubylode-windmill-status-name"), ["Heartbeat"])

await useScenario("all_green")
await open(dana, "/windmill_status")
expect("all green: nothing needs attention", await text(dana, ".rubylode-windmill-status-summary"), ["Nothing needs attention"])

await useScenario("unavailable")
await open(dana, "/windmill_status")
expect("unavailable: the fallback shows and the page still has its menu", [await text(dana, ".rubylode-windmill-status-summary"), await dana.locator("#main-menu, #top-menu").count() > 0], [["Status unavailable"], true])

await useScenario("hostile")
await open(dana, "/windmill_status")
expect("hostile: the script tag is shown as text and nothing ran", [await dana.locator("td.rubylode-windmill-status-error script").count(), await dana.locator("td.rubylode-windmill-status-error img").count()], [0, 0])

const visitor = await anonymousPage(browser)
await open(visitor, "/windmill_status")
expect("a signed-out visitor is sent to the login page", new URL(visitor.url()).pathname, "/login")

await useScenario("failures")
await browser.close()
process.exit(failures ? 1 : 0)
