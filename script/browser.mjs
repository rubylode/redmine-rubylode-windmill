// Shared helpers for the demo check and the screenshots. Talks only to the local demo Redmine (ruby bin/demo up).
import { chromium } from "playwright-core"
import { existsSync } from "node:fs"

export const baseUrl = process.env.DEMO_URL || "http://localhost:3015"

const chromeCandidates = [
  process.env.CHROME_PATH,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium"
]

export function launch() {
  const executablePath = chromeCandidates.find((candidate) => candidate && existsSync(candidate))
  if (!executablePath) throw new Error("No Chrome found. Set CHROME_PATH to a Chrome or Chromium binary.")
  return chromium.launch({ executablePath, headless: true })
}

export async function signedInPage(browser, login, password, viewport = { width: 1280, height: 700 }) {
  const context = await browser.newContext({ viewport, colorScheme: "light" })
  const page = await context.newPage()
  await page.goto(`${baseUrl}/login`)
  await page.fill("#username", login)
  await page.fill("#password", password)
  await Promise.all([page.waitForURL((url) => !url.pathname.startsWith("/login")), page.click("#login-submit")])
  return page
}

export async function anonymousPage(browser, viewport = { width: 1280, height: 700 }) {
  return (await browser.newContext({ viewport, colorScheme: "light" })).newPage()
}

export const fakeWindmillUrl = process.env.FAKE_WINDMILL_URL || "http://localhost:9115"

// Switches what the fake Windmill reports and waits out the demo cache (5 seconds).
export async function useScenario(name) {
  const response = await fetch(`${fakeWindmillUrl}/__scenario/${name}`, { method: "POST" })
  if (!response.ok) throw new Error(`scenario ${name}: ${response.status}`)
  await new Promise((resolve) => setTimeout(resolve, 6000))
}
