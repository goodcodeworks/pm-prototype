# PM Prototype Studio

Build functional design prototypes — or explore and change our real apps — by talking to Claude. No coding required. It's for anyone who isn't an engineer: product, QA, and customer support.

One command sets up everything on your Mac, including a brand-new one, and creates your first project:

```
curl -fsSL goodcode.works/pm | bash
```

Paste that into the **Terminal** app (press `⌘ Space`, type "Terminal", hit Enter), answer two questions, and you'll be talking to Claude inside a working project.

On a new Mac it will ask for your **Mac login password** once, to install Homebrew. Nothing appears on screen while you type it — that's normal. Type it and press Return.

**First time?** Watch the two-minute animated walkthrough first: **[goodcode.works/pm-tutorial](https://goodcode.works/pm-tutorial)**

## What it does

1. Installs anything missing: Homebrew, Node.js, the Claude Code CLI (plus a `cc` shortcut, so typing `cc` opens Claude), and [Superwhisper](https://superwhisper.com) so you can dictate your prompts instead of typing them
2. Asks what you want to call your project and what kind:
   - **Next.js** — interactive web app: dashboards, flows, multi-page (recommended)
   - **Plain HTML** — a single page that opens instantly, no server
   - **Start from one of our apps** — explore or change a real goodcodeworks app on your own branch (QA and support: pick this one)
3. Creates the project and drops you into Claude to start building. The first two come preloaded with realistic mock data (users, orders, KPIs, revenue)

**Safe to re-run any time.** Anything already installed and up to date is skipped, and you go straight to creating a project. If you type the name of a prototype you already made, it offers to reopen it instead.

## First time only

The first time you run `claude`, it will ask you to sign in with your Anthropic account in the browser. That's a one-time thing.

If you pick **Start from one of our apps**, you'll also be asked to sign in to GitHub once (`gh auth login`). The script walks you through it — pick *GitHub.com*, *HTTPS*, *Yes*, then *Login with a web browser*, and paste the code it gives you into the page that opens. Also a one-time thing.

## QA and customer support

Pick **Start from one of our apps**. You get your own copy of the real app and Claude can read all of it, so you can ask it things without changing anything:

- "How does this feature work? Explain it like I'm new here"
- "A customer says they saw this. What could cause that?"
- "Is this a bug?" — then "write that up as a bug report with steps to reproduce"

Claude can only see the code. It can't see the live system or a customer's account, and it will tell you so rather than guess.

The apps on the menu:

| App | What it is | Opens on your Mac? |
| --- | --- | --- |
| **POS** | The restaurant point-of-sale app | No — it's an Android tablet app |
| **KDS** | The kitchen display screens | No — it's an Android tablet app |
| **Dashboard** | The restaurant back-office dashboard | Yes, in your browser |
| **Online Ordering** | The customer-facing ordering site | Yes, in your browser |
| **Salon POS** | Booking calendar, clients, and stylist management | Yes, in your browser |

For POS and KDS you can still ask Claude anything about how they work and make changes for review; to see them running, ask an engineer for a test tablet.

The browser apps need a private settings file (`.env`) before they will run on your Mac. Setup tells you if yours does; ask an engineer for it. Asking questions works without it.

## Changing a real app

Option 3 makes you a full copy of one of our real apps, on your own branch (`pm/<your-name>-<project>`). The team's version is never touched — your copy refuses to push to it — and nothing goes live until someone reviews it.

When you're happy with your changes, just tell Claude:

> "Share this with the team"

Claude commits your work and opens a **pull request** — a page on GitHub showing exactly what you changed — then gives you the link to send round.

Your setup files are kept out of the pull request automatically, so reviewers only see the change you actually made.

## Seeing your prototype

- **Next.js**: in a second Terminal tab, run `npm run dev` inside the project folder, then open [http://localhost:3000](http://localhost:3000). It updates live as Claude works.
- **HTML**: double-click `index.html` in Finder and refresh after changes.
- **One of our apps**: ask Claude *"start the app so I can see it"* — it starts it and gives you the address to open (POS and KDS are tablet apps and don't open on a Mac). Your `GETTING_STARTED.md` also has the command if you'd rather run it yourself.

Every project also contains a `GETTING_STARTED.md` with these instructions and example prompts to try.

## Good first prompts

- "Build a dashboard page with the KPI cards and revenue chart"
- "Add a customers page with search and a detail panel"
- "Make a 3-step onboarding flow with a progress bar"

## Before you hand this to someone

Each person needs three things the script can't give them:

1. **A paid Claude account** (Pro, Max, or a Team/Enterprise seat). The free plan doesn't include Claude Code.
2. **For our real apps: a GitHub account with access to that app's repo.** The script walks them through creating the account and signing in; someone has to grant the access.
3. **An administrator account on their Mac**, which is the default for the first account on a new Mac. Homebrew can't install without it.

Apps that need a `.env` file to run also need an engineer to hand that over.

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
- Starting from a real app is different: Claude is told to follow that codebase's existing patterns rather than mock anything out. Setup files (`CLAUDE.md`, `GETTING_STARTED.md`, `.claude/settings.local.json`) are ignored locally via `.git/info/exclude`, so `git status` stays clean and the pull request shows only your change. If the app already has its own `CLAUDE.md` or `AGENTS.md`, it's left untouched and the notes go to `.claude/rules/pm-guide.md` instead, which Claude Code reads alongside it.
- On a real app the script also: installs the lockfile's package manager (yarn, pnpm, or bun) if the Mac lacks it, sets a git name and email from the GitHub account if none is set, and blocks pushes to `main`, `master`, and the repo's default branch (for example `develop`). Claude is also told never to run migrations, deploys, or release builds.
- The app menu is the `STARTER_REPOS` list at the top of `pm-prototype.sh`; add a line to offer another app. Being on the menu grants nothing — the person still needs GitHub access to that repo.
