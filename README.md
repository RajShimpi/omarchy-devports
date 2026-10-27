# Dev Ports

The servers you run while developing, in one Omarchy bar widget: which ports
are listening, which project and framework each one belongs to, and how long
it has been up. Open or copy a URL, open the project in your editor, or stop
a server cleanly.

Plugin id: `techspawn.devports`

## What it does

- **Bar:** a server icon with a badge that counts the projects with a dev
  server running. The tooltip names them.
- **Panel:** one card per process, dev servers first, then Docker containers.
  Each card shows:
  - the project folder (the nearest folder with `.git`, `package.json`,
    `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`, `Gemfile` …)
    and the framework, read from the command line: Vite, Next.js, Nuxt,
    Astro, React Router, Remix, SvelteKit, Angular, Storybook, Shopify CLI,
    Wrangler, NestJS, Django, Flask, Uvicorn, Gunicorn, Rails, Laravel, Hugo,
    Cloudflare Tunnel, MariaDB, PostgreSQL, Redis and more
  - process name, pid, uptime, the systemd unit when it runs as a service,
    and a *network* badge when it listens on more than localhost
  - the command line, with secrets masked (`--token=…`, `PASSWORD=…`,
    passwords in URLs)
  - its ports. Click a port to open it in the browser, right-click to copy
    the URL. Database and debugger ports (MySQL, Postgres, Redis, the Node
    inspector) are copied as `localhost:<port>` instead of opened.
- **Stop** asks first, then sends SIGTERM to the process and its child
  processes, and SIGKILL to whatever is still running after the grace period
  (5 s by default). **Kill** sends SIGKILL right away.
- IPv4 and IPv6 listeners of one process are merged. Forked servers that
  share a socket (workers) show once, under their parent process.
- **Show all** adds desktop apps that open local ports (editors, browsers,
  chat apps, apps started with your session) and system services owned by
  other users (PostgreSQL, Redis, CUPS, DNS …), named after their systemd
  unit. These are read-only: only your own processes can be stopped.
- **Docker:** ports published by containers are labelled with the container
  name, image and compose project folder, when your user can run
  `docker ps`. They cannot be stopped from here.
- Errors (no `ss`, a broken settings file, a failed stop) show in the panel.

### Keyboard

When the panel is open:

- `j` / `k` or Down / Up select a card
- `Enter` or `o` opens the first web port of the selected card
- `c` copies its URL
- `e` opens its project in the editor
- `s` or `x` stops it, `Shift+K` force-kills it. Both ask first: `Enter`
  confirms, `Esc` cancels, Left / Right or `Tab` switch buttons.
- `a` toggles **Show all**
- `r` refreshes now
- `Esc` closes the panel

## Install

```bash
omarchy plugin add https://github.com/RajShimpi/omarchy-devports
omarchy bar put techspawn.devports
```

You can also use **Install plugin** in the Omarchy menu with the repository URL.

## Remove

```bash
omarchy plugin remove techspawn.devports
```

To clear what it left behind (your settings and the cached Docker port map):

```bash
rm -f ~/.config/omarchy/devports.json ~/.cache/omarchy/devports-docker.json
```

## Settings

Click the pencil in the panel. The first time, this creates
`~/.config/omarchy/devports.json` with the defaults and opens it in your
editor. The plugin never writes that file otherwise. Missing keys use these
defaults:

```json
{
  "editor": "omarchy-launch-editor",
  "stopGraceSeconds": 5,
  "ignore": []
}
```

| Key | Meaning |
| --- | --- |
| `editor` | Command that opens a project folder; the folder is added at the end. The default opens the editor chosen with `omarchy default editor`. Other examples: `"code"`, `"cursor"`, `"zeditor"`, `"$VISUAL"`. Terminal editors (`nvim`, `hx` …) open in a terminal. |
| `stopGraceSeconds` | How long **Stop** waits after SIGTERM before it sends SIGKILL, 0 to 60. |
| `ignore` | Process names to treat as desktop apps (hidden until **Show all**), matched at the start of the name, e.g. `["syncthing", "my-daemon"]`. |

## Command line

The panel runs `scripts/devports`. You can use it too; it prints JSON:

```bash
scripts/devports list                # listening ports with process, project, framework
scripts/devports stop <pid> [port]   # SIGTERM, then SIGKILL after the grace period
scripts/devports kill <pid> [port]   # SIGKILL right away
```

With `[port]` it first checks that the process still listens on that port,
so a pid that was reused by another program is never signalled. It refuses
processes of other users and the ones that run your session.

## How it works and dependencies

- `scripts/devports` is a Python 3 script that uses only the standard
  library. It reads the listening sockets with `ss` (iproute2) and process
  details from `/proc`. Both are part of every Omarchy install.
- `xdg-open` opens URLs, `wl-copy` (wl-clipboard) copies them and
  `uwsm-app` starts the editor. Omarchy ships all three.
- Optional: `docker`, to name container ports. `docker ps` can take a few
  seconds, so its answer is cached in `~/.cache/omarchy/devports-docker.json`
  until the set of Docker sockets changes.
- The list refreshes every 3 s while the panel is open, and every 30 s
  otherwise for the badge. No root, no network access, nothing sent anywhere.

## License

MIT. See [LICENSE](LICENSE).
