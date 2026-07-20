# PM Prototype Studio

Build functional design prototypes by talking to Claude — no coding required.

One command sets up everything on your Mac and creates your first project:

```
curl -fsSL goodcode.works/pm | bash
```

Paste that into the **Terminal** app (press `⌘ Space`, type "Terminal", hit Enter), answer two questions, and you'll be talking to Claude inside a working prototype.

**First time?** Watch the two-minute animated walkthrough first: **[goodcode.works/pm-tutorial](https://goodcode.works/pm-tutorial)**

## What it does

1. Installs anything missing: Homebrew, Node.js, the Claude Code CLI (plus a `cc` shortcut, so typing `cc` opens Claude), and [Superwhisper](https://superwhisper.com) so you can dictate your prompts instead of typing them
2. Asks what you want to call your project and what kind:
   - **Next.js** — interactive web app: dashboards, flows, multi-page (recommended)
   - **Plain HTML** — a single page that opens instantly, no server
   - **Start from one of our apps** — change a real goodcodeworks app on your own branch
3. Creates the project and drops you into Claude to start building. The first two come preloaded with realistic mock data (users, orders, KPIs, revenue)

**Safe to re-run any time.** Anything already installed and up to date is skipped, and you go straight to creating a project. If you type the name of a prototype you already made, it offers to reopen it instead.

## First time only

The first time you run `claude`, it will ask you to sign in with your Anthropic account in the browser. That's a one-time thing.

If you pick **Start from one of our apps**, you'll also be asked to sign in to GitHub once (`gh auth login`). The script walks you through it — pick *GitHub.com*, *HTTPS*, *Yes*, then *Login with a web browser*, and paste the code it gives you into the page that opens. Also a one-time thing.

## Changing a real app

Option 3 makes you a full copy of one of our real apps, on your own branch (`pm/<your-name>-<project>`). The team's main version is never touched, and nothing goes live until someone reviews it.

When you're happy with your changes, just tell Claude:

> "Share this with the team"

Claude commits your work and opens a **pull request** — a page on GitHub showing exactly what you changed — then gives you the link to send round.

Your setup files are kept out of the pull request automatically, so reviewers only see the change you actually made.

## Seeing your prototype

- **Next.js**: in a second Terminal tab, run `npm run dev` inside the project folder, then open [http://localhost:3000](http://localhost:3000). It updates live as Claude works.
- **HTML**: double-click `index.html` in Finder and refresh after changes.
- **One of our apps**: same as Next.js — `npm run dev`, then [http://localhost:3000](http://localhost:3000). Your `GETTING_STARTED.md` tells you which folder to run it from.

Every project also contains a `GETTING_STARTED.md` with these instructions and example prompts to try.

## Good first prompts

- "Build a dashboard page with the KPI cards and revenue chart"
- "Add a customers page with search and a detail panel"
- "Make a 3-step onboarding flow with a progress bar"

## For the curious

- Projects are created in `~/Prototypes` (override with `PROTOTYPE_HOME=/some/path`)
- Non-interactive usage:
  ```
  ./pm-prototype.sh setup                    # just install/verify the tools
  ./pm-prototype.sh new <name>               # create a Next.js prototype
  ./pm-prototype.sh new <name> --html        # create a plain-HTML prototype
  ./pm-prototype.sh new <name> --repo <app>  # copy one of our apps onto a branch
  ```
  Run `./pm-prototype.sh --help` to see the available apps.
- Prototypes are throwaway by design: all data is mocked in `lib/mock-data.ts` (or `mock-data.js`), and the bundled `CLAUDE.md` instructs Claude to keep it that way — no databases, no auth, nothing to deploy or break.
- Starting from a real app is different: Claude is told to follow that codebase's existing patterns rather than mock anything out. Setup files (`CLAUDE.md`, `GETTING_STARTED.md`, `.claude/settings.local.json`) are ignored locally via `.git/info/exclude`, so `git status` stays clean and the pull request shows only your change. If the app already has its own `CLAUDE.md`, it's left untouched and the PM notes go to `.claude/pm-guide.md` instead.
