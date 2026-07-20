#!/usr/bin/env bash
#
# pm-prototype.sh — one-command setup for PMs to build functional designs
# with Claude Code on a Mac.
#
# What it does:
#   1. Installs anything missing: Homebrew, Node.js, Claude Code CLI,
#      and Superwhisper (dictation — speak your prompts instead of typing)
#   2. Creates a project one of three ways:
#        - Next.js (TypeScript + Tailwind) for interactive, multi-page prototypes
#        - Plain HTML for zero-install single-page mockups
#        - A copy of a real goodcodeworks app, on your own branch, ready for a PR
#   3. Drops in Claude instructions tuned for the path you picked, so Claude
#      explains things in plain language and stays inside the guardrails.
#
# Usage:
#   ./pm-prototype.sh                          # interactive — best for first run
#   ./pm-prototype.sh setup                    # just install/verify the tools
#   ./pm-prototype.sh new <name>               # create a Next.js prototype
#   ./pm-prototype.sh new <name> --html        # create a plain-HTML prototype
#   ./pm-prototype.sh new <name> --repo <key>  # start from one of our apps
#
# Or run it straight from the web — safe to re-run any time; anything already
# installed and up to date is skipped and you go straight to creating a project:
#   curl -fsSL goodcode.works/pm | bash
#   curl -fsSL goodcode.works/pm | bash -s -- new my-idea
#
# Projects are created in ~/Prototypes (override with PROTOTYPE_HOME=/path).

set -euo pipefail

PROTOTYPE_HOME="${PROTOTYPE_HOME:-$HOME/Prototypes}"

# ─── Curated starter apps ────────────────────────────────────────────────────
# Real goodcodeworks apps a PM can copy and change on their own branch.
# Format: key|owner/repo|subdir|Label — description
#   subdir = folder inside the repo that holds the runnable app ("" = repo root)
# To offer another app, just add a line here — nothing else in the script
# needs to change.

STARTER_REPOS=(
  "salon-pos|goodcodeworks/salon-pos|salon-software|Salon POS — booking calendar, clients, and stylist management"
)

# Anything unusual about a particular repo that Claude needs warning about —
# a misleading README, a conventions file with rules that fight this workflow,
# and so on. Keyed by the manifest key; add a case branch per repo that needs
# one. Repos with nothing odd about them need no entry at all.
starter_notes() {
  case "$1" in
    salon-pos)
      cat <<'EOF'

## Two things about this repo specifically

**Ignore the files at the top of the repo.** `new-project.sh`,
`new-project-cli.sh`, and the root `README.md` are leftovers from an unrelated
project-scaffolding tool. They do not describe this app and will mislead you.
The app is everything under `salon-software/` — a salon/spa/barber operating
system called Halo (booking calendar, clients, booth-rental ledger, walk-ins
and waitlist, online booking portal). All of its data is deterministic mock
data; there is no backend.

**Read `CONVENTIONS.md` and follow its code-style rules** — especially: add no
new dependencies, no raw hex colors (use the semantic tokens), no emoji as
icons (use `lucide-react`), no `Math.random()` / `Date.now()` / `new Date()` at
module scope (use `seededRandom` / `getToday()` from `@/lib/dates`), and no
external image assets.

`CONVENTIONS.md` says it wins on conflict, but it was written for a team of
parallel build agents, not for this PM workflow. **These three of its rules do
not apply here:**

1. Its rule against running `npm run dev` / `npm run build` — in this workflow
   running the dev server is expected and encouraged. The PM needs to see their
   change. Run it.
2. Its rule "don't commit, leave the working tree dirty" — in this workflow you
   commit to the PM's `pm/…` branch. That is the entire point.
3. Its per-agent ownership map restricting which paths you may touch — that is
   for their multi-agent build. The PM may ask for changes anywhere inside
   `salon-software/`.
EOF
      ;;
  esac
}

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
  printf "  ./pm-prototype.sh new <name>                # Next.js prototype\n"
  printf "  ./pm-prototype.sh new <name> --html         # plain-HTML prototype\n"
  printf "  ./pm-prototype.sh new <name> --repo <app>   # start from one of our apps\n"
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

ensure_superwhisper() {
  # Superwhisper (superwhisper.com): dictation, so PMs can speak their prompts.
  # Optional nice-to-have — never blocks setup if it can't install.
  if [[ -d "/Applications/superwhisper.app" || -d "$HOME/Applications/superwhisper.app" ]]; then
    ok "Superwhisper is installed"
    return
  fi
  ensure_homebrew
  say "Installing Superwhisper (dictation — speak your prompts instead of typing)..."
  if brew install --cask superwhisper >/dev/null 2>&1; then
    ok "Superwhisper installed — open it once from Applications to set up your mic"
  else
    warn "Couldn't install Superwhisper automatically — it's optional; grab it at https://superwhisper.com"
  fi
}

ensure_gh() {
  # GitHub CLI — only needed when starting from one of our real apps. It's what
  # lets us copy a private repo and later open a pull request for the PM.
  if ! command -v gh >/dev/null 2>&1; then
    ensure_homebrew
    say "Installing the GitHub tool..."
    brew install gh || die "Couldn't install the GitHub tool automatically.
  Ask an engineer for a hand, or install it yourself with: brew install gh"
    ok "GitHub tool installed"
  else
    ok "GitHub tool is installed"
  fi

  if gh auth status >/dev/null 2>&1; then
    ok "You're signed in to GitHub"
    return
  fi

  echo
  say "You need to sign in to GitHub once so we can copy the app for you."
  printf "  GitHub will ask a few short questions in this window. The safe answers:\n"
  printf "    • Where do you use GitHub? → %sGitHub.com%s\n" "$BOLD" "$NC"
  printf "    • Preferred protocol?      → %sHTTPS%s\n" "$BOLD" "$NC"
  printf "    • Authenticate Git?        → %sYes%s\n" "$BOLD" "$NC"
  printf "    • How to authenticate?     → %sLogin with a web browser%s\n" "$BOLD" "$NC"
  printf "  Then copy the code it shows you and paste it into the browser page it opens.\n\n"

  # Under `curl | bash` stdin is the script itself, so hand gh the real terminal.
  if [[ -t 0 ]]; then
    gh auth login || true
  elif [[ -r /dev/tty ]]; then
    gh auth login </dev/tty >/dev/tty 2>&1 || true
  else
    die "Signing in to GitHub needs an interactive terminal.
  Open the Terminal app, run: gh auth login
  ...then run this script again."
  fi

  gh auth status >/dev/null 2>&1 || die "GitHub sign-in didn't complete, so I can't copy the app.
  Open the Terminal app and run: gh auth login
  Once that finishes, run this script again."
  ok "Signed in to GitHub"
}

ensure_cc_alias() {
  # 'cc' as a shortcut for 'claude' in new Terminal windows. If any cc alias
  # already exists (theirs or ours), leave it alone.
  local rc="$HOME/.zshrc"
  if grep -q '^alias cc=' "$rc" 2>/dev/null; then
    ok "'cc' shortcut for claude is set up"
    return
  fi
  say "Adding 'cc' as a shortcut for claude..."
  printf '\nalias cc="claude"  # added by pm-prototype.sh\n' >> "$rc"
  ok "'cc' shortcut added — works in new Terminal windows"
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
  ensure_cc_alias
  ensure_superwhisper
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
  # For kind=repo the extra args are: <app dir> <dev command> <branch> [outfile]
  local dir="$1" name="$2" kind="$3" appdir="${4:-}" devcmd="${5:-}" branch="${6:-}"
  local out="${7:-$dir/GETTING_STARTED.md}"
  {
    printf '# Getting started with %s\n\n' "$name"
    if [[ "$kind" == "repo" ]]; then
      cat <<EOF
This is a real goodcodeworks app — a full copy of it, on your own branch.
Nothing you do here touches the live version until someone reviews it.

Open the Terminal app and run:

\`\`\`
cd "$appdir"
claude
\`\`\`

(Tip: \`cc\` works as a shortcut for \`claude\`.)

Then describe the change you want, for example:

- "Walk me through what this app does"
- "On the booking screen, show the stylist's next free slot"
- "Make the checkout total easier to read on a phone"

## Seeing the app

In a second Terminal tab:

\`\`\`
cd "$appdir"
$devcmd
\`\`\`

Then open **http://localhost:3000** in your browser. It updates live as
Claude makes changes.

## Your branch

You're on the branch \`$branch\` — your own copy of the code. The team's
main version is untouched.

## Sharing your changes

When you're happy with it, just tell Claude:

> "Share this with the team"

Claude will save your work and open a pull request — a page on GitHub where
the team can see exactly what you changed and comment on it. Claude will give
you the link to send round.
EOF
    elif [[ "$kind" == "next" ]]; then
      cat <<EOF
Open the Terminal app and run:

\`\`\`
cd "$dir"
claude
\`\`\`

(Tip: \`cc\` works as a shortcut for \`claude\`.)

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

(Tip: \`cc\` works as a shortcut for \`claude\`.)

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
  } > "$out"
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

# ─── Starter app (real repo) ─────────────────────────────────────────────────
# Set by scaffold_repo, read by print_next_steps.
REPO_APP_DIR=""
REPO_DEV_CMD=""
REPO_BRANCH=""
REPO_STARTED_FILE=""

starter_field() { # starter_field <manifest line> <1-4>
  printf '%s' "$1" | cut -d'|' -f"$2"
}

starter_lookup() { # starter_lookup <key> -> prints the manifest line; 1 if unknown
  local entry
  for entry in "${STARTER_REPOS[@]}"; do
    if [[ "$(starter_field "$entry" 1)" == "$1" ]]; then
      printf '%s' "$entry"
      return 0
    fi
  done
  return 1
}

starter_label() { # everything after the last '|' — the human-readable bit
  printf '%s' "${1##*|}"
}

repo_tracks() { # repo_tracks <repo dir> <path relative to repo> — is it in git?
  git -C "$1" ls-files --error-unmatch "$2" >/dev/null 2>&1
}

git_local_exclude() { # ignore files locally without touching the tracked .gitignore
  local dir="$1"; shift
  local ex="$dir/.git/info/exclude" p
  mkdir -p "$(dirname "$ex")"
  if ! grep -qxF '# added by pm-prototype.sh' "$ex" 2>/dev/null; then
    printf '\n# added by pm-prototype.sh\n' >> "$ex"
  fi
  for p in "$@"; do
    grep -qxF "$p" "$ex" 2>/dev/null || printf '%s\n' "$p" >> "$ex"
  done
}

write_push_guard() { # refuse pushes to main/master from this clone
  # These repos are on a plan without branch protection, so nothing on GitHub's
  # side stops a push to main. Both guards live inside .git/, so they never show
  # up in the PM's pull request.
  local dir="$1" b
  local hook="$dir/.git/hooks/pre-push"
  mkdir -p "$(dirname "$hook")"
  cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
# Added by pm-prototype.sh — keeps the shared app safe.
# Blocks pushes to main/master. Your own pm/ branch pushes normally.
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  case "$remote_ref" in
    refs/heads/main|refs/heads/master)
      printf '\n\033[0;31m✗\033[0m That would change the real app for everyone.\n\n'
      printf 'Your work goes on your own branch instead. Ask Claude to\n'
      printf '"share this with the team" and it opens a pull request, so an\n'
      printf 'engineer can read the changes before anything reaches customers.\n\n'
      exit 1
      ;;
  esac
done
exit 0
HOOK
  chmod 755 "$hook"
  # Second layer: if the hook is ever removed, pushing while on main still fails.
  for b in main master; do
    if git -C "$dir" show-ref --verify --quiet "refs/heads/$b"; then
      git -C "$dir" config "branch.$b.pushRemote" no-push-main || true
    fi
  done
}

find_app_dir() { # find_app_dir <repo dir> <subdir> -> prints app dir; 1 if no package.json
  local dir="$1" subdir="$2"
  if [[ -n "$subdir" ]]; then
    printf '%s' "$dir/$subdir"
    return 0
  fi
  if [[ -f "$dir/package.json" ]]; then
    printf '%s' "$dir"
    return 0
  fi
  # Exactly one top-level folder with a package.json? Use that. Otherwise give up.
  local found="" d
  for d in "$dir"/*/; do
    [[ -f "${d}package.json" ]] || continue
    [[ -z "$found" ]] || return 1
    found="${d%/}"
  done
  [[ -n "$found" ]] || return 1
  printf '%s' "$found"
}

pkg_manager_for() { # pick the lockfile's package manager, but only if it's installed
  local appdir="$1"
  if   [[ -f "$appdir/bun.lockb"      ]] && command -v bun  >/dev/null 2>&1; then printf 'bun'
  elif [[ -f "$appdir/pnpm-lock.yaml" ]] && command -v pnpm >/dev/null 2>&1; then printf 'pnpm'
  elif [[ -f "$appdir/yarn.lock"      ]] && command -v yarn >/dev/null 2>&1; then printf 'yarn'
  else printf 'npm'
  fi
}

restore_lockfiles() {
  # An install can rewrite a tracked lockfile (e.g. when the repo's lockfile has
  # drifted from its package.json). That's not the PM's change, so put it back —
  # otherwise it turns up as noise in their pull request.
  local dir="$1"
  git -C "$dir" diff --name-only 2>/dev/null | while IFS= read -r f; do
    case "${f##*/}" in
      package-lock.json|npm-shrinkwrap.json|pnpm-lock.yaml|yarn.lock|bun.lockb)
        git -C "$dir" checkout -- "$f" 2>/dev/null || true
        ;;
    esac
  done
}

write_repo_settings() {
  local dir="$1" pm="$2"
  mkdir -p "$dir/.claude"
  # settings.local.json, not settings.json — local overrides that Claude Code
  # keeps out of git, so the PM's pull request stays clean.
  cat > "$dir/.claude/settings.local.json" <<EOF
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash($pm run dev:*)",
      "Bash($pm run build:*)",
      "Bash($pm run lint:*)",
      "Bash($pm install:*)",
      "Bash(npx tsc:*)",
      "Bash(open http://localhost:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(gh pr create:*)",
      "Bash(gh pr view:*)"
    ]
  }
}
EOF
}

write_repo_claude_md() {
  local out="$1" repo="$2" branch="$3" subdir="$4" pm="$5" key="${6:-}"
  {
    printf '# Working with a PM on %s\n\n' "$repo"
    cat <<EOF
This is a **real, production codebase** — not a throwaway prototype. A product
manager is making a change to it on the branch \`$branch\`.
EOF
    if [[ -n "$subdir" ]]; then
      # the backticks are markdown, not a command substitution
      # shellcheck disable=SC2016
      printf '\nThe runnable app lives in `%s/`. Run commands from there.\n' "$subdir"
    fi
    cat <<EOF

## The user is a PM, not an engineer

- Explain what you did in plain language. Avoid jargon.
- Never ask them to edit code themselves — make the change for them.
- Never paste code at them to explain a change; describe the behaviour instead.
- When something needs a decision, offer 2–3 concrete options with a recommendation.

## Follow this codebase — do not invent your own way of doing things

- **Read the neighbouring files before you change anything.** Match the
  patterns, naming, file layout, and libraries already in use.
- Do **not** introduce a new framework, state library, styling approach, or
  component kit. Use what's already here.
- Do **not** create a mock-data file or stub out fake data. This app has real
  data flows — follow them.
- Reuse existing components and helpers instead of writing new ones. Search
  first, write second.
- Keep changes as small and focused as the request. No drive-by refactors.

## Verifying your work

- Run \`$pm run dev\` and check the change actually works.
- Before sharing, run \`$pm run build\` (and \`$pm run lint\` if it exists) and
  fix anything you broke.

## Sharing the work

The PM is on branch \`$branch\`. Commit there as you go.

When they say **"share this"**, **"send it to the team"**, or **"I'm done"**:

1. \`git add\` the relevant files and commit with a clear, plain-language message.
2. \`git push\` the branch.
3. Run \`gh pr create\` with a title and a short description of *what changed and
   why*, written for a human reviewer.
4. Give the PM the pull request URL and tell them to send that link to the team.

## Hard rules

- Never commit to \`main\`. Never check out \`main\`. Stay on \`$branch\`.
- **Pushing to \`main\` is blocked in this copy.** A git hook refuses it. If you
  hit that block, do not retry it, do not try to work around it, and do not
  remove the hook — it means the change belongs on \`$branch\` and should reach
  \`main\` through a pull request. Switch to the commit-and-\`gh pr create\` path.
- Never force-push. Never rewrite history.
- Never commit secrets, API keys, \`.env\` files, or credentials.
- Never delete or rewrite unrelated code to make something work.
EOF
    # Anything odd about this specific repo (see starter_notes above).
    if [[ -n "$key" ]]; then starter_notes "$key"; fi
  } > "$out"
}

scaffold_repo() {
  local name="$1" dir="$2" entry="$3"
  local key repo subdir label
  key="$(starter_field "$entry" 1)"
  repo="$(starter_field "$entry" 2)"
  subdir="$(starter_field "$entry" 3)"
  label="$(starter_label "$entry")"

  ensure_gh

  say "Getting a copy of $label..."
  gh repo clone "$repo" "$dir" -- --quiet || die "Couldn't copy $repo.
  You may not have access to it yet — ask an engineer to add you to the goodcodeworks org."
  ok "Copied $repo"

  # ── Your own branch, so main is never touched ──
  local who slug branch
  who="$(slugify "$(git -C "$dir" config user.name 2>/dev/null || true)")"
  [[ -n "$who" ]] || who="$(slugify "${USER:-pm}")"
  [[ -n "$who" ]] || who="pm"
  slug="$(slugify "$name")"
  branch="pm/${who}-${slug}"
  if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$dir" checkout --quiet "$branch"
  else
    git -C "$dir" checkout --quiet -b "$branch"
  fi
  ok "You're on your own branch: $branch"

  # Nothing on GitHub's side protects main on these repos, so guard it here.
  write_push_guard "$dir"

  # ── Where the runnable app actually is ──
  local appdir="" pm="npm" can_install=1
  if appdir="$(find_app_dir "$dir" "$subdir")" && [[ -f "$appdir/package.json" ]]; then
    pm="$(pkg_manager_for "$appdir")"
  else
    appdir="$dir"
    can_install=0
  fi

  if [[ "$can_install" == "1" ]]; then
    node_ok || ensure_node
    # Install straight from the lockfile so it isn't rewritten under the PM.
    local -a install_cmd
    case "$pm" in
      npm)  if [[ -f "$appdir/package-lock.json" ]]; then install_cmd=(npm ci); else install_cmd=(npm install); fi ;;
      pnpm) install_cmd=(pnpm install --frozen-lockfile) ;;
      yarn) install_cmd=(yarn install --frozen-lockfile) ;;
      bun)  install_cmd=(bun install --frozen-lockfile) ;;
      *)    install_cmd=("$pm" install) ;;
    esac
    say "Installing the app's building blocks (takes a minute or two)..."
    if (cd "$appdir" && "${install_cmd[@]}"); then
      ok "App is ready to run"
    elif (cd "$appdir" && "$pm" install); then
      ok "App is ready to run"
    else
      warn "The install didn't finish cleanly. Try it yourself later: cd \"$appdir\" && $pm install"
    fi
    restore_lockfiles "$dir"
  else
    warn "Couldn't find an app to install in this repo — skipping the install step."
    printf "  Ask Claude what this project needs to run.\n"
  fi

  # ── PM guidance, written so it never shows up in their pull request ──
  say "Adding your Claude instructions..."

  # The PM opens Claude inside the app folder, so the config belongs there —
  # not at the top of the repo. Paths added to .git/info/exclude have to be
  # relative to the repo root, hence the prefix.
  local rel=""
  [[ "$appdir" == "$dir" ]] || rel="${appdir#"$dir"/}/"

  write_repo_settings "$appdir" "$pm"
  local created=("${rel}.claude/settings.local.json")

  local guide="$appdir/CLAUDE.md" guide_rel="${rel}CLAUDE.md"
  if [[ -e "$guide" ]] || repo_tracks "$dir" "$guide_rel"; then
    guide="$appdir/.claude/pm-guide.md"
    guide_rel="${rel}.claude/pm-guide.md"
    warn "This app already has its own CLAUDE.md — leaving it exactly as it is."
    printf "  Your PM notes went to %s instead. The app's own\n" "$guide_rel"
    printf "  CLAUDE.md takes precedence, which is what you want.\n"
  fi
  created+=("$guide_rel")
  write_repo_claude_md "$guide" "$repo" "$branch" "$subdir" "$pm" "$key"

  local started="$dir/GETTING_STARTED.md"
  if repo_tracks "$dir" "GETTING_STARTED.md"; then
    started="$dir/.claude/GETTING_STARTED.md"
    created+=(".claude/GETTING_STARTED.md")
  else
    created+=("GETTING_STARTED.md")
  fi
  write_getting_started "$dir" "$name" "repo" "$appdir" "$pm run dev" "$branch" "$started"

  # Ignore our additions locally only — the tracked .gitignore is untouched,
  # so `git status` stays clean and the PM's pull request has no noise in it.
  git_local_exclude "$dir" "${created[@]}"

  REPO_APP_DIR="$appdir"
  REPO_DEV_CMD="$pm run dev"
  REPO_BRANCH="$branch"
  REPO_STARTED_FILE="$started"
  ok "$label is ready at $dir"
}

# ─── Create command ──────────────────────────────────────────────────────────

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -cd 'a-z0-9-' | sed 's/^-*//; s/-*$//'
}

print_next_steps() {
  local dir="$1" kind="$2"
  local cddir="$dir"
  [[ "$kind" == "repo" && -n "$REPO_APP_DIR" ]] && cddir="$REPO_APP_DIR"
  echo
  printf "%s─────────────────────────────────────────────%s\n" "$BOLD" "$NC"
  if [[ "$kind" == "repo" ]]; then
    printf "%sYour copy of the app is ready.%s Next steps:\n\n" "$BOLD" "$NC"
  else
    printf "%sYour prototype is ready.%s Next steps:\n\n" "$BOLD" "$NC"
  fi
  printf "  1. %scd \"%s\"%s\n" "$BOLD" "$cddir" "$NC"
  printf "  2. %sclaude%s   (or just %scc%s — sign in if it's your first time)\n" "$BOLD" "$NC" "$BOLD" "$NC"
  if [[ "$kind" == "repo" ]]; then
    printf "  3. Describe the change you want\n"
    printf "\n  Preview: run %s%s%s in a second tab, open http://localhost:3000\n" "$BOLD" "$REPO_DEV_CMD" "$NC"
    printf "  You're on branch %s%s%s — main is untouched.\n" "$BOLD" "$REPO_BRANCH" "$NC"
    printf "  When you're done, tell Claude %s\"share this with the team\"%s and it\n" "$BOLD" "$NC"
    printf "  will open a pull request and give you the link.\n"
  else
    printf "  3. Describe what you want to build\n"
    if [[ "$kind" == "next" ]]; then
      printf "\n  Preview: run %snpm run dev%s in a second tab, open http://localhost:3000\n" "$BOLD" "$NC"
    else
      printf "\n  Preview: %sopen \"%s/index.html\"%s\n" "$BOLD" "$dir" "$NC"
    fi
  fi
  local guide="$dir/GETTING_STARTED.md"
  [[ "$kind" == "repo" && -n "$REPO_STARTED_FILE" ]] && guide="$REPO_STARTED_FILE"
  printf "\n  Full instructions are in %s%s%s\n" "$BOLD" "$guide" "$NC"
  printf "%s─────────────────────────────────────────────%s\n" "$BOLD" "$NC"
}

starter_keys() { # space-separated list of manifest keys, for help text
  local e out=""
  for e in "${STARTER_REPOS[@]}"; do out+="$(starter_field "$e" 1) "; done
  printf '%s' "${out% }"
}

normalize_repo_ref() { # owner/repo or a GitHub URL -> owner/repo (engineer escape hatch)
  local ref="$1"
  ref="${ref%.git}"
  ref="${ref#git@github.com:}"
  ref="${ref#https://github.com/}"
  ref="${ref#http://github.com/}"
  ref="${ref#github.com/}"
  ref="$(printf '%s' "$ref" | cut -d'/' -f1,2)"
  [[ "$ref" == */* && "$ref" != */ ]] || return 1
  printf '%s' "$ref"
}

cmd_new() {
  local raw_name="${1:-}" kind="next" repo_key="" entry=""
  [[ -n "$raw_name" ]] || die "Usage: ./pm-prototype.sh new <name> [--html | --repo <app>]"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --html)   kind="html" ;;
      --repo)   kind="repo"; repo_key="${2:-}"; shift || : ;;
      --repo=*) kind="repo"; repo_key="${1#--repo=}" ;;
      *) die "Unknown option: $1 (try: --html, or --repo <app>)" ;;
    esac
    # a bare trailing --repo leaves nothing to shift; don't let set -e kill us
    shift || break
  done

  if [[ "$kind" == "repo" ]]; then
    [[ -n "$repo_key" ]] || die "Which app do you want to start from?
  Try: ./pm-prototype.sh new $raw_name --repo $(starter_field "${STARTER_REPOS[0]}" 1)
  Available: $(starter_keys)"
    if ! entry="$(starter_lookup "$repo_key")"; then
      # Not in the curated list — fall back to treating it as owner/repo or a URL.
      local ref=""
      ref="$(normalize_repo_ref "$repo_key")" || die "Don't know the app '$repo_key'.
  Available: $(starter_keys)"
      entry="$repo_key|$ref||$ref"
    fi
  fi

  local name
  name="$(slugify "$raw_name")"
  [[ -n "$name" ]] || die "Couldn't make a valid project name out of '$raw_name'. Use letters, numbers, and dashes."
  [[ "$name" == "$raw_name" ]] || say "Using project name: $name"

  mkdir -p "$PROTOTYPE_HOME"
  local dir="$PROTOTYPE_HOME/$name"
  [[ ! -e "$dir" ]] || die "$dir already exists. Pick a different name."

  case "$kind" in
    next)
      node_ok || die "Node.js 20+ is required. Run: ./pm-prototype.sh setup"
      scaffold_next "$name" "$dir"
      ;;
    repo)
      scaffold_repo "$name" "$dir" "$entry"
      ;;
    *)
      scaffold_html "$name" "$dir"
      ;;
  esac

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
    printf "  ./pm-prototype.sh new <name>                # Next.js prototype\n"
    printf "  ./pm-prototype.sh new <name> --html         # plain-HTML prototype\n"
    printf "  ./pm-prototype.sh new <name> --repo <app>   # start from one of our apps\n"
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
  choice="$(ask $'\nWhat do you want to build?\n  1) Next.js — interactive web app: dashboards, flows, multi-page (recommended)\n  2) Plain HTML — single page, opens instantly, no server\n  3) Start from one of our apps — change a real goodcodeworks app\n> ')" || { ask_aborted; return 0; }

  local repo_key=""
  if [[ "$choice" == "3" ]]; then
    local menu="" i=1 e
    for e in "${STARTER_REPOS[@]}"; do
      menu+="  $i) $(starter_label "$e")"$'\n'
      i=$((i + 1))
    done
    local pick=""
    while :; do
      pick="$(ask $'\nWhich app do you want to change?\n'"$menu"'> ')" || { ask_aborted; return 0; }
      [[ -n "$pick" ]] || pick="1"
      if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#STARTER_REPOS[@]} )); then
        repo_key="$(starter_field "${STARTER_REPOS[$((pick - 1))]}" 1)"
        break
      fi
      warn "Pick a number from the list above."
    done
  fi

  echo
  case "$choice" in
    2) cmd_new "$raw_name" "--html" ;;
    3) cmd_new "$raw_name" "--repo" "$repo_key" ;;
    *) cmd_new "$raw_name" ;;
  esac

  # For a real app, Claude should open inside the runnable app folder.
  local opendir="$dir"
  [[ "$choice" == "3" && -n "$REPO_APP_DIR" ]] && opendir="$REPO_APP_DIR"

  local ans=""
  ans="$(ask $'\nStart building with Claude right now? [Y/n] ')" || return 0
  case "$(printf '%s' "${ans:-y}" | tr '[:upper:]' '[:lower:]')" in
    n*) printf "Okay — when you're ready: cd \"%s\" && claude\n" "$opendir" ;;
    *)  launch_claude "$opendir" ;;
  esac
}

# ─── Main ────────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
pm-prototype.sh — build functional designs with Claude Code

Usage:
  ./pm-prototype.sh                          Interactive: check tools, then create a project
  ./pm-prototype.sh setup                    Just install/verify Homebrew, Node, Claude Code
  ./pm-prototype.sh new <name>               Create a Next.js prototype
  ./pm-prototype.sh new <name> --html        Create a plain-HTML prototype
  ./pm-prototype.sh new <name> --repo <app>  Copy one of our apps onto your own branch

Run it straight from the web (safe to re-run; args pass through after --):
  curl -fsSL goodcode.works/pm | bash
  curl -fsSL goodcode.works/pm | bash -s -- new my-idea

Projects are created in ~/Prototypes (override with PROTOTYPE_HOME=/path).
EOF
  printf '\nStarter apps for --repo: %s\n' "$(starter_keys)"
  cat <<'EOF'

For engineers: --repo also accepts any owner/repo or GitHub URL, e.g.
  ./pm-prototype.sh new spike --repo goodcodeworks/some-app
  ./pm-prototype.sh new spike --repo https://github.com/goodcodeworks/some-app
It clones with `gh`, makes a pm/<user>-<name> branch, installs deps with the
lockfile's package manager, and writes local-only Claude config (git-clean).
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
