# PM Prototype Studio

Build functional design prototypes by talking to Claude — no coding required.

One command sets up everything on your Mac and creates your first project:

```
curl -fsSL goodcode.works/pm | bash
```

Paste that into the **Terminal** app (press `⌘ Space`, type "Terminal", hit Enter), answer two questions, and you'll be talking to Claude inside a working prototype.

## What it does

1. Installs anything missing: Homebrew, Node.js, and the Claude Code CLI (plus a `cc` shortcut, so typing `cc` opens Claude)
2. Asks what you want to call your prototype and what kind:
   - **Next.js** — interactive web app: dashboards, flows, multi-page (recommended)
   - **Plain HTML** — a single page that opens instantly, no server
3. Creates the project preloaded with realistic mock data (users, orders, KPIs, revenue) and drops you into Claude to start building

**Safe to re-run any time.** Anything already installed and up to date is skipped, and you go straight to creating a project. If you type the name of a prototype you already made, it offers to reopen it instead.

## First time only

The first time you run `claude`, it will ask you to sign in with your Anthropic account in the browser. That's a one-time thing.

## Seeing your prototype

- **Next.js**: in a second Terminal tab, run `npm run dev` inside the project folder, then open [http://localhost:3000](http://localhost:3000). It updates live as Claude works.
- **HTML**: double-click `index.html` in Finder and refresh after changes.

Every project also contains a `GETTING_STARTED.md` with these instructions and example prompts to try.

## Good first prompts

- "Build a dashboard page with the KPI cards and revenue chart"
- "Add a customers page with search and a detail panel"
- "Make a 3-step onboarding flow with a progress bar"

## For the curious

- Projects are created in `~/Prototypes` (override with `PROTOTYPE_HOME=/some/path`)
- Non-interactive usage:
  ```
  ./pm-prototype.sh setup               # just install/verify the tools
  ./pm-prototype.sh new <name>          # create a Next.js prototype
  ./pm-prototype.sh new <name> --html   # create a plain-HTML prototype
  ```
- Prototypes are throwaway by design: all data is mocked in `lib/mock-data.ts` (or `mock-data.js`), and the bundled `CLAUDE.md` instructs Claude to keep it that way — no databases, no auth, nothing to deploy or break.
