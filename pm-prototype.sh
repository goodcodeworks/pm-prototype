#!/usr/bin/env bash
#
# pm-prototype.sh — one-command setup for PMs to build functional designs
# with Claude Code on a Mac.
#
# What it does:
#   1. Installs anything missing: Homebrew, Node.js, Claude Code CLI
#   2. Creates a prototype project preloaded with realistic mock data:
#        - Next.js (TypeScript + Tailwind) for interactive, multi-page prototypes
#        - Plain HTML for zero-install single-page mockups
#   3. Drops in a CLAUDE.md tuned for PM prototyping, so Claude keeps
#      everything client-side, uses the mock data, and explains things
#      in plain language.
#
# Usage:
#   ./pm-prototype.sh                     # interactive — best for first run
#   ./pm-prototype.sh setup               # just install/verify the tools
#   ./pm-prototype.sh new <name>          # create a Next.js prototype
#   ./pm-prototype.sh new <name> --html   # create a plain-HTML prototype
#
# Or run it straight from the web — safe to re-run any time; anything already
# installed and up to date is skipped and you go straight to creating a project:
#   curl -fsSL https://raw.githubusercontent.com/goodcodeworks/pm-prototype/main/pm-prototype.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/goodcodeworks/pm-prototype/main/pm-prototype.sh | bash -s -- new my-idea
#
# Projects are created in ~/Prototypes (override with PROTOTYPE_HOME=/path).

set -euo pipefail

PROTOTYPE_HOME="${PROTOTYPE_HOME:-$HOME/Prototypes}"

# Colors (ANSI-C quoted so the bytes are real ESC, not literal \033)
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

say()  { printf "${CYAN}▶${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
die()  { printf "${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."

# ─── Terminal helpers ────────────────────────────────────────────────────────
# The script must work when piped from curl. When piped, stdin is the script
# itself, so interactive prompts have to go through /dev/tty instead.

have_tty() { [[ -t 0 || -r /dev/tty ]]; }

ask() { # ask "<prompt>" -> prints the reply on stdout; returns 1 on EOF/no tty
  local reply=""
  if [[ -t 0 ]]; then
    printf '%s' "$1" >&2
    read -r reply || return 1
  elif [[ -r /dev/tty ]]; then
    printf '%s' "$1" > /dev/tty
    read -r reply < /dev/tty || return 1
  else
    return 1
  fi
  printf '%s' "$reply"
}

ask_aborted() { # input stream ended mid-conversation — bail out politely
  echo
  warn "Input ended — nothing else was changed."
  printf "To create a project non-interactively, run:\n"
  printf "  ./pm-prototype.sh new <name>          # Next.js prototype\n"
  printf "  ./pm-prototype.sh new <name> --html   # plain-HTML prototype\n"
}

launch_claude() { # hands the terminal over to claude inside the project
  local dir="$1"
  cd "$dir"
  if [[ -t 0 ]]; then exec claude; fi
  if [[ -r /dev/tty ]]; then exec claude </dev/tty; fi
  printf 'Run: cd "%s" && claude\n' "$dir"
}

# ─── Tool installation ────────────────────────────────────────────────────────

load_brew_path() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$b" ]]; then
      eval "$("$b" shellenv)"
      return 0
    fi
  done
  return 1
}

ensure_homebrew() {
  command -v brew >/dev/null 2>&1 || load_brew_path || true
  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew is installed"
    return
  fi
  say "Installing Homebrew (this may ask for your Mac login password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew_path || die "Homebrew installed but not found on PATH. Open a new Terminal window and re-run this script."
  # Make brew available in future terminal sessions
  if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
    # the $(...) must stay literal in .zprofile
    # shellcheck disable=SC2016
    printf 'eval "$(%s shellenv)"\n' "$(command -v brew)" >> "$HOME/.zprofile"
  fi
  ok "Homebrew installed"
}

node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local major
  major="$(node -p 'parseInt(process.versions.node, 10)' 2>/dev/null)" || return 1
  [[ "$major" -ge 20 ]]
}

ensure_node() {
  if node_ok; then
    ok "Node.js $(node --version) is installed"
    return
  fi
  ensure_homebrew
  if command -v node >/dev/null 2>&1; then
    say "Your Node.js ($(node --version)) is too old — updating..."
    brew install node 2>/dev/null || brew upgrade node || true
  else
    say "Installing Node.js..."
    brew install node
  fi
  node_ok || die "Node.js 20+ is required but couldn't be installed automatically.
  If you use nvm or another Node manager, update it there (e.g. nvm install --lts) and re-run."
  ok "Node.js $(node --version) installed"
}

CLAUDE_JUST_INSTALLED=0

ensure_claude() {
  # Native installer puts claude in ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code $(claude --version 2>/dev/null | head -1) is installed"
    return
  fi
  CLAUDE_JUST_INSTALLED=1
  say "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
  command -v claude >/dev/null 2>&1 || die "Claude Code install failed. Try: npm install -g @anthropic-ai/claude-code"
  # Make claude available in future terminal sessions
  if ! grep -q '.local/bin' "$HOME/.zprofile" 2>/dev/null; then
    # $HOME/$PATH must stay literal in .zprofile
    # shellcheck disable=SC2016
    printf 'export PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zprofile"
  fi
  ok "Claude Code installed"
}

update_claude() {
  # A fresh install is already current — only check on re-runs.
  [[ "$CLAUDE_JUST_INSTALLED" == "1" ]] && return 0
  say "Checking Claude Code for updates..."
  if claude update >/dev/null 2>&1; then
    ok "Claude Code is up to date ($(claude --version 2>/dev/null | head -1))"
  else
    warn "Couldn't check for updates right now — continuing with the installed version"
  fi
}

cmd_setup() {
  say "Checking your setup..."
  ensure_node
  ensure_claude
  update_claude
  echo
  ok "Everything is installed and up to date."
  printf "  %sFirst time?%s Run %sclaude%s in any folder and follow the sign-in prompts once.\n" "$BOLD" "$NC" "$BOLD" "$NC"
}

# ─── Project files (shared) ──────────────────────────────────────────────────

write_mock_data_ts() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
// Mock data for prototyping. Everything in the app should read from here.
// Add new datasets to this file as the prototype grows — never a real backend.

export type User = {
  id: string;
  name: string;
  email: string;
  role: "Admin" | "Member" | "Viewer";
  avatarColor: string;
  lastActive: string;
  status: "active" | "invited" | "deactivated";
};

export const users: User[] = [
  { id: "u1", name: "Ava Martinez", email: "ava@acme.co", role: "Admin", avatarColor: "#6366f1", lastActive: "2 minutes ago", status: "active" },
  { id: "u2", name: "Liam Chen", email: "liam@acme.co", role: "Member", avatarColor: "#22c55e", lastActive: "1 hour ago", status: "active" },
  { id: "u3", name: "Sofia Rossi", email: "sofia@acme.co", role: "Member", avatarColor: "#f59e0b", lastActive: "Yesterday", status: "active" },
  { id: "u4", name: "Noah Williams", email: "noah@acme.co", role: "Viewer", avatarColor: "#ec4899", lastActive: "3 days ago", status: "active" },
  { id: "u5", name: "Emma Johnson", email: "emma@acme.co", role: "Member", avatarColor: "#14b8a6", lastActive: "Last week", status: "invited" },
  { id: "u6", name: "Mateo García", email: "mateo@acme.co", role: "Admin", avatarColor: "#8b5cf6", lastActive: "4 hours ago", status: "active" },
  { id: "u7", name: "Olivia Brown", email: "olivia@acme.co", role: "Viewer", avatarColor: "#ef4444", lastActive: "2 weeks ago", status: "deactivated" },
  { id: "u8", name: "Yuki Tanaka", email: "yuki@acme.co", role: "Member", avatarColor: "#0ea5e9", lastActive: "30 minutes ago", status: "active" },
];

export type Product = {
  id: string;
  name: string;
  category: string;
  price: number;
  stock: number;
  rating: number;
};

export const products: Product[] = [
  { id: "p1", name: "Starter Plan", category: "Subscription", price: 29, stock: 999, rating: 4.2 },
  { id: "p2", name: "Pro Plan", category: "Subscription", price: 99, stock: 999, rating: 4.7 },
  { id: "p3", name: "Enterprise Plan", category: "Subscription", price: 499, stock: 999, rating: 4.5 },
  { id: "p4", name: "Onboarding Package", category: "Service", price: 1200, stock: 14, rating: 4.9 },
  { id: "p5", name: "API Add-on", category: "Add-on", price: 49, stock: 999, rating: 4.1 },
  { id: "p6", name: "Priority Support", category: "Add-on", price: 149, stock: 999, rating: 4.8 },
];

export type Order = {
  id: string;
  customer: string;
  product: string;
  amount: number;
  date: string;
  status: "paid" | "pending" | "refunded" | "failed";
};

export const orders: Order[] = [
  { id: "ord-1042", customer: "Brightline Labs", product: "Pro Plan", amount: 99, date: "2026-07-06", status: "paid" },
  { id: "ord-1041", customer: "Nimbus Health", product: "Enterprise Plan", amount: 499, date: "2026-07-06", status: "paid" },
  { id: "ord-1040", customer: "Copperfield & Co", product: "Starter Plan", amount: 29, date: "2026-07-05", status: "pending" },
  { id: "ord-1039", customer: "Juniper Retail", product: "Onboarding Package", amount: 1200, date: "2026-07-05", status: "paid" },
  { id: "ord-1038", customer: "Atlas Freight", product: "Pro Plan", amount: 99, date: "2026-07-04", status: "failed" },
  { id: "ord-1037", customer: "Marigold Media", product: "API Add-on", amount: 49, date: "2026-07-03", status: "paid" },
  { id: "ord-1036", customer: "Pinewood Studios", product: "Priority Support", amount: 149, date: "2026-07-02", status: "refunded" },
  { id: "ord-1035", customer: "Harbor Fintech", product: "Enterprise Plan", amount: 499, date: "2026-07-01", status: "paid" },
  { id: "ord-1034", customer: "Solstice Energy", product: "Pro Plan", amount: 99, date: "2026-06-30", status: "paid" },
  { id: "ord-1033", customer: "Quartz Analytics", product: "Starter Plan", amount: 29, date: "2026-06-29", status: "pending" },
];

export type Kpi = {
  label: string;
  value: string;
  change: string;
  trend: "up" | "down" | "flat";
};

export const kpis: Kpi[] = [
  { label: "Monthly Revenue", value: "$48,290", change: "+12.4%", trend: "up" },
  { label: "Active Users", value: "2,847", change: "+8.1%", trend: "up" },
  { label: "Churn Rate", value: "2.3%", change: "-0.4%", trend: "down" },
  { label: "Avg. Response Time", value: "1.2h", change: "0.0%", trend: "flat" },
];

export type MonthlyRevenue = { month: string; revenue: number; target: number };

export const revenueByMonth: MonthlyRevenue[] = [
  { month: "Aug", revenue: 31200, target: 30000 },
  { month: "Sep", revenue: 33800, target: 32000 },
  { month: "Oct", revenue: 32100, target: 34000 },
  { month: "Nov", revenue: 36900, target: 36000 },
  { month: "Dec", revenue: 41500, target: 38000 },
  { month: "Jan", revenue: 39800, target: 40000 },
  { month: "Feb", revenue: 42300, target: 42000 },
  { month: "Mar", revenue: 44100, target: 44000 },
  { month: "Apr", revenue: 43700, target: 46000 },
  { month: "May", revenue: 46200, target: 48000 },
  { month: "Jun", revenue: 47800, target: 50000 },
  { month: "Jul", revenue: 48290, target: 52000 },
];

export type Activity = {
  id: string;
  user: string;
  action: string;
  time: string;
};

export const activityFeed: Activity[] = [
  { id: "a1", user: "Ava Martinez", action: "invited Emma Johnson to the workspace", time: "2 minutes ago" },
  { id: "a2", user: "Liam Chen", action: "upgraded Brightline Labs to Pro Plan", time: "1 hour ago" },
  { id: "a3", user: "Mateo García", action: "changed billing settings", time: "4 hours ago" },
  { id: "a4", user: "Sofia Rossi", action: "exported the Q2 revenue report", time: "Yesterday" },
  { id: "a5", user: "Yuki Tanaka", action: "commented on order ord-1038", time: "Yesterday" },
  { id: "a6", user: "Noah Williams", action: "viewed the analytics dashboard", time: "3 days ago" },
];
EOF
}

write_next_claude_md() {
  local dir="$1" name="$2"
  {
    printf '# %s — PM Prototype\n\n' "$name"
    cat <<'EOF'
You are helping a **product manager** build a functional design prototype.
This is a throwaway prototype for exploring product ideas — optimize for
speed and visual quality, not production readiness.

## The user is a PM, not an engineer

- Explain what you did in plain language. Avoid jargon.
- Never ask them to edit code themselves — make the change for them.
- When something needs a decision, offer 2–3 concrete options with a recommendation.

## Hard rules

- **All data comes from `lib/mock-data.ts`.** Never add a real database, API
  calls to external services, auth, or environment secrets. If a screen needs
  data that doesn't exist yet, add realistic mock data to `lib/mock-data.ts`.
- Keep everything runnable with just `npm run dev` — no extra services.
- Use Tailwind for styling. Make it look polished and modern by default.
- Prefer client components with local `useState` for interactivity (forms,
  filters, toggles should *work*, storing state in memory).
- Don't install heavy dependencies without saying why. Small, well-known
  libraries (e.g. an icon set or chart library) are fine.

## Verifying your work

- After changes, confirm the app still compiles (the dev server hot-reloads;
  if in doubt run `npm run build`).
- Remind the PM the preview lives at http://localhost:3000 and to start it
  with `npm run dev` if it isn't running.

## Good prompts the PM might give you

- "Build a dashboard page with the KPI cards and revenue chart"
- "Add a customers page with search and a detail panel"
- "Make a 3-step onboarding flow with a progress bar"
EOF
  } > "$dir/CLAUDE.md"
}

write_next_settings() {
  local dir="$1"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash(npm run dev:*)",
      "Bash(npm run build:*)",
      "Bash(npm run lint:*)",
      "Bash(npm install:*)",
      "Bash(npx tsc:*)",
      "Bash(open http://localhost:*)"
    ]
  }
}
EOF
}

write_next_page() {
  local page="$1"
  mkdir -p "$(dirname "$page")"
  cat > "$page" <<'EOF'
import { kpis, orders, users } from "@/lib/mock-data";

const trendColor: Record<string, string> = {
  up: "text-emerald-600",
  down: "text-emerald-600",
  flat: "text-zinc-400",
};

const statusStyle: Record<string, string> = {
  paid: "bg-emerald-50 text-emerald-700",
  pending: "bg-amber-50 text-amber-700",
  refunded: "bg-zinc-100 text-zinc-600",
  failed: "bg-red-50 text-red-700",
};

export default function Home() {
  return (
    <main className="mx-auto max-w-5xl px-6 py-12">
      <p className="text-sm font-medium text-indigo-600">Prototype ready</p>
      <h1 className="mt-1 text-3xl font-bold tracking-tight">
        Your prototype is running
      </h1>
      <p className="mt-2 max-w-2xl text-zinc-500">
        This starter page proves the mock data is wired up. Open Claude in this
        folder and describe the screens you want — for example:{" "}
        <em>&ldquo;Replace this page with a customer dashboard.&rdquo;</em>
      </p>

      <section className="mt-10 grid grid-cols-2 gap-4 lg:grid-cols-4">
        {kpis.map((kpi) => (
          <div key={kpi.label} className="rounded-xl border border-zinc-200 p-4">
            <p className="text-sm text-zinc-500">{kpi.label}</p>
            <p className="mt-1 text-2xl font-semibold">{kpi.value}</p>
            <p className={`mt-1 text-sm ${trendColor[kpi.trend]}`}>{kpi.change}</p>
          </div>
        ))}
      </section>

      <section className="mt-10">
        <h2 className="text-lg font-semibold">Recent orders</h2>
        <div className="mt-3 overflow-x-auto rounded-xl border border-zinc-200">
          <table className="w-full text-left text-sm">
            <thead className="bg-zinc-50 text-zinc-500">
              <tr>
                <th className="px-4 py-2 font-medium">Order</th>
                <th className="px-4 py-2 font-medium">Customer</th>
                <th className="px-4 py-2 font-medium">Product</th>
                <th className="px-4 py-2 font-medium">Amount</th>
                <th className="px-4 py-2 font-medium">Status</th>
              </tr>
            </thead>
            <tbody>
              {orders.slice(0, 5).map((order) => (
                <tr key={order.id} className="border-t border-zinc-100">
                  <td className="px-4 py-2 font-mono text-xs">{order.id}</td>
                  <td className="px-4 py-2">{order.customer}</td>
                  <td className="px-4 py-2">{order.product}</td>
                  <td className="px-4 py-2">${order.amount}</td>
                  <td className="px-4 py-2">
                    <span
                      className={`rounded-full px-2 py-0.5 text-xs font-medium ${statusStyle[order.status]}`}
                    >
                      {order.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mt-10">
        <h2 className="text-lg font-semibold">Team</h2>
        <div className="mt-3 flex flex-wrap gap-3">
          {users.slice(0, 6).map((user) => (
            <div
              key={user.id}
              className="flex items-center gap-2 rounded-full border border-zinc-200 py-1 pl-1 pr-3"
            >
              <span
                className="flex h-7 w-7 items-center justify-center rounded-full text-xs font-semibold text-white"
                style={{ backgroundColor: user.avatarColor }}
              >
                {user.name.charAt(0)}
              </span>
              <span className="text-sm">{user.name}</span>
            </div>
          ))}
        </div>
      </section>
    </main>
  );
}
EOF
}

write_getting_started() {
  local dir="$1" name="$2" kind="$3"
  {
    printf '# Getting started with %s\n\n' "$name"
    if [[ "$kind" == "next" ]]; then
      cat <<EOF
Open the Terminal app and run:

\`\`\`
cd "$dir"
claude
\`\`\`

Then just describe what you want, for example:

- "Build a dashboard page using the KPI and revenue mock data"
- "Add a customers page with search and filters"
- "Make a settings screen with a plan-upgrade flow"

## Seeing your prototype

In a second Terminal tab:

\`\`\`
cd "$dir"
npm run dev
\`\`\`

Then open **http://localhost:3000** in your browser. It updates live as
Claude makes changes.

## Where the data lives

All fake data (users, orders, KPIs, revenue) is in \`lib/mock-data.ts\`.
Ask Claude to add more whenever a screen needs it.
EOF
    else
      cat <<EOF
Open the Terminal app and run:

\`\`\`
cd "$dir"
claude
\`\`\`

Then just describe what you want, for example:

- "Turn this into a landing page for a scheduling app"
- "Add a pricing section with three tiers"
- "Build a signup form that shows a success state"

## Seeing your prototype

Double-click \`index.html\` in Finder, or run:

\`\`\`
open "$dir/index.html"
\`\`\`

Refresh the browser after Claude makes changes.

## Where the data lives

All fake data is in \`mock-data.js\`. Ask Claude to add more whenever the
page needs it.
EOF
    fi
  } > "$dir/GETTING_STARTED.md"
}

# ─── Next.js prototype ───────────────────────────────────────────────────────

scaffold_next() {
  local name="$1" dir="$2"
  say "Creating Next.js app '$name' (takes a minute or two)..."
  (
    cd "$PROTOTYPE_HOME"
    npx --yes create-next-app@latest "$name" \
      --typescript --tailwind --eslint --app --no-src-dir \
      --import-alias "@/*" --use-npm --yes
  )

  # Respect whichever layout create-next-app produced
  local base="$dir"
  [[ -d "$dir/src/app" ]] && base="$dir/src"
  local appdir="$base/app"
  [[ -d "$appdir" ]] || die "Unexpected project layout — couldn't find the app/ directory in $dir"

  say "Adding mock data and PM configuration..."
  write_mock_data_ts "$base/lib/mock-data.ts"
  write_next_page "$appdir/page.tsx"
  write_next_claude_md "$dir" "$name"
  write_next_settings "$dir"
  write_getting_started "$dir" "$name" "next"
  ok "Next.js prototype created at $dir"
}

# ─── Plain HTML prototype ────────────────────────────────────────────────────

write_html_claude_md() {
  local dir="$1" name="$2"
  {
    printf '# %s — PM Prototype (plain HTML)\n\n' "$name"
    cat <<'EOF'
You are helping a **product manager** build a functional design mockup.
This is a throwaway prototype — optimize for speed and visual quality.

## The user is a PM, not an engineer

- Explain what you did in plain language. Avoid jargon.
- Never ask them to edit code themselves — make the change for them.

## Hard rules

- **Plain HTML/CSS/JS only.** No build steps, no npm, no frameworks.
  Everything must work by opening `index.html` directly in a browser.
- All fake data lives in `mock-data.js`. If a section needs data that
  doesn't exist yet, add realistic mock data there.
- Keep styles in the `<style>` block (or a linked `styles.css`) — modern,
  polished, responsive.
- Interactivity via small vanilla JS is encouraged (tabs, modals, form
  validation with fake success states).
- Extra pages are fine (`pricing.html`, `dashboard.html`) — link them
  together with normal `<a>` tags.

## After every change

Remind the PM to refresh the page in their browser (or run `open index.html`).
EOF
  } > "$dir/CLAUDE.md"
}

scaffold_html() {
  local name="$1" dir="$2"
  say "Creating HTML prototype '$name'..."
  mkdir -p "$dir"

  cat > "$dir/mock-data.js" <<'EOF'
// Mock data for prototyping. Everything on the page should read from here.
// Add new datasets as the prototype grows — never a real backend.

const MOCK = {
  kpis: [
    { label: "Monthly Revenue", value: "$48,290", change: "+12.4%", trend: "up" },
    { label: "Active Users", value: "2,847", change: "+8.1%", trend: "up" },
    { label: "Churn Rate", value: "2.3%", change: "-0.4%", trend: "down" },
    { label: "Avg. Response Time", value: "1.2h", change: "0.0%", trend: "flat" },
  ],
  users: [
    { id: "u1", name: "Ava Martinez", email: "ava@acme.co", role: "Admin", lastActive: "2 minutes ago", status: "active" },
    { id: "u2", name: "Liam Chen", email: "liam@acme.co", role: "Member", lastActive: "1 hour ago", status: "active" },
    { id: "u3", name: "Sofia Rossi", email: "sofia@acme.co", role: "Member", lastActive: "Yesterday", status: "active" },
    { id: "u4", name: "Noah Williams", email: "noah@acme.co", role: "Viewer", lastActive: "3 days ago", status: "active" },
    { id: "u5", name: "Emma Johnson", email: "emma@acme.co", role: "Member", lastActive: "Last week", status: "invited" },
    { id: "u6", name: "Mateo García", email: "mateo@acme.co", role: "Admin", lastActive: "4 hours ago", status: "active" },
  ],
  orders: [
    { id: "ord-1042", customer: "Brightline Labs", product: "Pro Plan", amount: 99, date: "2026-07-06", status: "paid" },
    { id: "ord-1041", customer: "Nimbus Health", product: "Enterprise Plan", amount: 499, date: "2026-07-06", status: "paid" },
    { id: "ord-1040", customer: "Copperfield & Co", product: "Starter Plan", amount: 29, date: "2026-07-05", status: "pending" },
    { id: "ord-1039", customer: "Juniper Retail", product: "Onboarding Package", amount: 1200, date: "2026-07-05", status: "paid" },
    { id: "ord-1038", customer: "Atlas Freight", product: "Pro Plan", amount: 99, date: "2026-07-04", status: "failed" },
  ],
  revenueByMonth: [
    { month: "Feb", revenue: 42300 }, { month: "Mar", revenue: 44100 },
    { month: "Apr", revenue: 43700 }, { month: "May", revenue: 46200 },
    { month: "Jun", revenue: 47800 }, { month: "Jul", revenue: 48290 },
  ],
};
EOF

  cat > "$dir/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Prototype</title>
  <style>
    :root { --ink: #18181b; --muted: #71717a; --line: #e4e4e7; --accent: #6366f1; }
    * { box-sizing: border-box; margin: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--ink); background: #fafafa; padding: 48px 24px;
    }
    .wrap { max-width: 960px; margin: 0 auto; }
    .eyebrow { color: var(--accent); font-weight: 600; font-size: 14px; }
    h1 { font-size: 30px; letter-spacing: -0.02em; margin-top: 4px; }
    .lede { color: var(--muted); margin-top: 8px; max-width: 60ch; }
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 14px; margin-top: 36px; }
    .card { background: #fff; border: 1px solid var(--line); border-radius: 12px; padding: 16px; }
    .card .label { color: var(--muted); font-size: 13px; }
    .card .value { font-size: 24px; font-weight: 650; margin-top: 4px; }
    .card .change { font-size: 13px; margin-top: 4px; color: #059669; }
    .card .change.flat { color: var(--muted); }
    h2 { font-size: 18px; margin-top: 40px; }
    table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid var(--line); border-radius: 12px; overflow: hidden; margin-top: 12px; font-size: 14px; }
    th, td { text-align: left; padding: 10px 14px; }
    thead { background: #f4f4f5; color: var(--muted); font-size: 13px; }
    tbody tr { border-top: 1px solid #f4f4f5; }
    .pill { border-radius: 999px; padding: 2px 10px; font-size: 12px; font-weight: 500; }
    .pill.paid { background: #ecfdf5; color: #047857; }
    .pill.pending { background: #fffbeb; color: #b45309; }
    .pill.failed { background: #fef2f2; color: #b91c1c; }
    .pill.refunded { background: #f4f4f5; color: #52525b; }
  </style>
</head>
<body>
  <div class="wrap">
    <p class="eyebrow">Prototype ready</p>
    <h1>Your prototype is working</h1>
    <p class="lede">
      This starter page proves the mock data is wired up. Open Claude in this
      folder and describe what you want — for example: “Turn this into a
      landing page for a scheduling app.”
    </p>

    <div class="cards" id="kpis"></div>

    <h2>Recent orders</h2>
    <table>
      <thead>
        <tr><th>Order</th><th>Customer</th><th>Product</th><th>Amount</th><th>Status</th></tr>
      </thead>
      <tbody id="orders"></tbody>
    </table>
  </div>

  <script src="mock-data.js"></script>
  <script>
    document.getElementById("kpis").innerHTML = MOCK.kpis.map(function (k) {
      var cls = k.trend === "flat" ? "change flat" : "change";
      return '<div class="card"><div class="label">' + k.label + '</div>' +
             '<div class="value">' + k.value + '</div>' +
             '<div class="' + cls + '">' + k.change + '</div></div>';
    }).join("");

    document.getElementById("orders").innerHTML = MOCK.orders.map(function (o) {
      return "<tr><td>" + o.id + "</td><td>" + o.customer + "</td><td>" + o.product +
             "</td><td>$" + o.amount + '</td><td><span class="pill ' + o.status + '">' +
             o.status + "</span></td></tr>";
    }).join("");
  </script>
</body>
</html>
EOF

  write_html_claude_md "$dir" "$name"
  write_getting_started "$dir" "$name" "html"
  ok "HTML prototype created at $dir"
}

# ─── Create command ──────────────────────────────────────────────────────────

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -cd 'a-z0-9-' | sed 's/^-*//; s/-*$//'
}

print_next_steps() {
  local dir="$1" kind="$2"
  echo
  printf "%s─────────────────────────────────────────────%s\n" "$BOLD" "$NC"
  printf "%sYour prototype is ready.%s Next steps:\n\n" "$BOLD" "$NC"
  printf "  1. %scd \"%s\"%s\n" "$BOLD" "$dir" "$NC"
  printf "  2. %sclaude%s   (sign in if it's your first time)\n" "$BOLD" "$NC"
  printf "  3. Describe what you want to build\n"
  if [[ "$kind" == "next" ]]; then
    printf "\n  Preview: run %snpm run dev%s in a second tab, open http://localhost:3000\n" "$BOLD" "$NC"
  else
    printf "\n  Preview: %sopen \"%s/index.html\"%s\n" "$BOLD" "$dir" "$NC"
  fi
  printf "\n  Full instructions are in %s%s/GETTING_STARTED.md%s\n" "$BOLD" "$dir" "$NC"
  printf "%s─────────────────────────────────────────────%s\n" "$BOLD" "$NC"
}

cmd_new() {
  local raw_name="${1:-}" kind="next"
  [[ -n "$raw_name" ]] || die "Usage: ./pm-prototype.sh new <name> [--html]"
  [[ "${2:-}" == "--html" ]] && kind="html"

  local name
  name="$(slugify "$raw_name")"
  [[ -n "$name" ]] || die "Couldn't make a valid project name out of '$raw_name'. Use letters, numbers, and dashes."
  [[ "$name" == "$raw_name" ]] || say "Using project name: $name"

  mkdir -p "$PROTOTYPE_HOME"
  local dir="$PROTOTYPE_HOME/$name"
  [[ ! -e "$dir" ]] || die "$dir already exists. Pick a different name."

  if [[ "$kind" == "next" ]]; then
    node_ok || die "Node.js 20+ is required. Run: ./pm-prototype.sh setup"
    scaffold_next "$name" "$dir"
  else
    scaffold_html "$name" "$dir"
  fi

  print_next_steps "$dir" "$kind"
}

# ─── Interactive flow ────────────────────────────────────────────────────────

cmd_interactive() {
  printf "\n%s%sPM Prototype Studio%s\n" "$BOLD" "$CYAN" "$NC"
  printf "Build functional designs by talking to Claude.\n\n"

  cmd_setup
  echo

  if ! have_tty; then
    warn "No interactive terminal detected — setup is done, but I can't ask questions."
    printf "To create a project, run:\n"
    printf "  ./pm-prototype.sh new <name>          # Next.js prototype\n"
    printf "  ./pm-prototype.sh new <name> --html   # plain-HTML prototype\n"
    return 0
  fi

  local raw_name="" name="" dir=""
  while :; do
    raw_name="$(ask $'What do you want to call your prototype? (e.g. checkout-redesign)\n> ')" || { ask_aborted; return 0; }
    [[ -n "$raw_name" ]] || raw_name="my-prototype"
    name="$(slugify "$raw_name")"
    if [[ -z "$name" ]]; then
      warn "Use letters, numbers, and dashes for the name."
      continue
    fi
    dir="$PROTOTYPE_HOME/$name"
    if [[ -e "$dir" ]]; then
      local reopen=""
      reopen="$(ask "\"$name\" already exists. Open it with Claude instead? [Y/n] ")" || { ask_aborted; return 0; }
      case "$(printf '%s' "${reopen:-y}" | tr '[:upper:]' '[:lower:]')" in
        n*) continue ;;
        *)  launch_claude "$dir"; return 0 ;;
      esac
    fi
    break
  done

  local choice=""
  choice="$(ask $'\nWhat kind of prototype?\n  1) Next.js — interactive web app: dashboards, flows, multi-page (recommended)\n  2) Plain HTML — single page, opens instantly, no server\n> ')" || { ask_aborted; return 0; }

  echo
  if [[ "$choice" == "2" ]]; then
    cmd_new "$raw_name" "--html"
  else
    cmd_new "$raw_name"
  fi

  local ans=""
  ans="$(ask $'\nStart building with Claude right now? [Y/n] ')" || return 0
  case "$(printf '%s' "${ans:-y}" | tr '[:upper:]' '[:lower:]')" in
    n*) printf "Okay — when you're ready: cd \"%s\" && claude\n" "$dir" ;;
    *)  launch_claude "$dir" ;;
  esac
}

# ─── Main ────────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
pm-prototype.sh — build functional designs with Claude Code

Usage:
  ./pm-prototype.sh                     Interactive: check tools, then create a project
  ./pm-prototype.sh setup               Just install/verify Homebrew, Node, Claude Code
  ./pm-prototype.sh new <name>          Create a Next.js prototype
  ./pm-prototype.sh new <name> --html   Create a plain-HTML prototype

Run it straight from the web (safe to re-run; args pass through after --):
  curl -fsSL https://raw.githubusercontent.com/goodcodeworks/pm-prototype/main/pm-prototype.sh | bash
  curl -fsSL https://raw.githubusercontent.com/goodcodeworks/pm-prototype/main/pm-prototype.sh | bash -s -- new my-idea

Projects are created in ~/Prototypes (override with PROTOTYPE_HOME=/path).
EOF
}

case "${1:-}" in
  setup)        cmd_setup ;;
  new)          shift; cmd_new "$@" ;;
  ""|start)     cmd_interactive ;;
  -h|--help|help) usage ;;
  *)
    die "Unknown command: $1 (try: setup, new <name> [--html], or run with no arguments)"
    ;;
esac
