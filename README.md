# homelab

Single repo that runs and manages self-hosted apps in containers, each on its
own domain (`*.localhost` here, `*.local` from anything else on the WiFi),
behind one reverse proxy. Adding an app is a small YAML file; rolling out a new
version is one command.

## Layout

```
homelab/
├── compose.yaml        # proxy (traefik) + include: list of apps + shared network
├── traefik.yaml        # proxy static config (uses the file provider)
├── dynamic/
│   └── routes.yaml     # per-app routers + services (Host -> container)
├── Makefile            # up / down / rollout / logs helpers
├── scripts/
│   ├── mdns-aliases.sh      # publishes <app>.local for the LAN
│   └── homelab-mdns.service # systemd unit for it (make mdns-install)
├── .env.example        # secrets referenced by apps (copy to .env)
└── apps/
    ├── _template.yaml  # copy this to add a new app
    ├── entrypoint.yaml # entrypoint.localhost  -> React/Vite static (nginx)
    ├── kashkul.yaml    # kashkul.localhost      -> Astro blog (node)
    └── ouioui.yaml     # ouioui.localhost       -> FastAPI (uvicorn)
```

App source lives in **sibling directories** of this repo
(`../entrypoint-v2`, `../kashkul`, `../ouioui`) and is used as each app's build
context. This repo only holds orchestration.

## How routing works

[Traefik](https://traefik.io) reads `dynamic/routes.yaml` (the **file
provider**) — one router + service per app, mapping a host to a container name
on the shared `homelab` network. Each router matches `HostRegexp(^<app>\..+$)`:
any hostname whose first label is the app name. `*.localhost` already resolves
to loopback on Linux and in browsers, so `http://ouioui.localhost` hits Traefik
on `:80`, which forwards to the ouioui container. `routes.yaml` is watched, so
edits apply live without restarting Traefik.

### From phones and other devices on the LAN

`*.localhost` only resolves on this machine. For the rest of the house the apps
answer to short **mDNS** names instead:

    http://ouioui.local        http://kashkul.local        http://entrypoint.local

`scripts/mdns-aliases.sh` publishes one `<app>.local` alias per router in
`dynamic/routes.yaml`, all pointing at this machine's LAN IP; Traefik then
routes by Host header as usual. Install it once, it then runs at boot:

```sh
make mdns-install     # copies scripts/homelab-mdns.service, enables it (sudo)
make mdns-status      # check it
```

The app list comes from `routes.yaml`, so a new app needs no edit here, just
`sudo systemctl restart homelab-mdns`. The LAN IP is looked up at runtime and
the service restarts itself if a DHCP renewal changes it, so no address is
hardcoded anywhere in this repo.

Resolving `.local` needs an mDNS client: built in on iOS, macOS and most Linux
desktops (`avahi-daemon` must be running on this host). Android does not
resolve `.local` reliably. As a fallback that works on anything with internet
DNS, [nip.io](https://nip.io) maps `*.<ip>.nip.io` back to `<ip>`:

    http://ouioui.192.168.1.19.nip.io

Apps that ship their own Host allowlist need these domains added. `kashkul`
runs the Astro dev server, whose Vite host check rejects unknown hosts with a
403; its `astro.config.mjs` allows `.localhost`, `.local` and `.nip.io` under
`vite.server.allowedHosts`.

> We use the file provider, not Traefik's docker provider, because Docker
> Engine 29 dropped the legacy API version (1.24) that Traefik's docker client
> hardcodes — the docker provider errors with "client version 1.24 is too old".
> (Alternative: set `DOCKER_MIN_API_VERSION=1.24` on the docker daemon and use
> container labels instead. The file provider avoids touching the daemon.)

Traefik dashboard: http://traefik.localhost

## Prerequisites

Docker Engine + compose plugin. Not installed on this machine yet — on CachyOS/Arch:

```sh
sudo pacman -S docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER   # then re-login so `docker` works without sudo
```

## Usage

```sh
cp .env.example .env      # fill DEEPL_API_KEY etc.
make up                   # build + start proxy and all apps
make ps                   # status
make logs app=kashkul     # tail one app (omit app= for all)
```

Then open:

| App        | This machine                | Phone / LAN              |
|------------|-----------------------------|--------------------------|
| entrypoint | http://entrypoint.localhost | http://entrypoint.local  |
| kashkul    | http://kashkul.localhost    | http://kashkul.local     |
| ouioui     | http://ouioui.localhost     | http://ouioui.local      |
| traefik    | http://traefik.localhost    | http://traefik.local     |

## Rollout a new version

Pull/edit the app source in its sibling dir, then rebuild just that app with
zero downtime for the others:

```sh
make rollout app=ouioui
```

This rebuilds the image and recreates only that container.

## Add a new app

1. `cp apps/_template.yaml apps/myapp.yaml`
2. Edit it: replace `NAME` with the app slug, set build `context` (its source
   dir).
3. Add `- apps/myapp.yaml` to the `include:` list in `compose.yaml`.
4. Add a router + service for it in `dynamic/routes.yaml` (copy an existing
   pair; point the service url at `http://myapp:<port>`).
5. `make rollout app=myapp` → live at `http://myapp.localhost`.
6. `sudo systemctl restart homelab-mdns` → also live at `http://myapp.local`
   for the rest of the LAN.

If the app has no Dockerfile, add one to its source dir first (see
`../entrypoint-v2/Dockerfile` for a static-SPA example).

## Notes

- **ouioui** stores its SQLite DB in a named volume (`ouioui-data`, mounted at
  `/data`), so data survives rebuilds. Reads `DEEPL_API_KEY` from `.env`.
- **kashkul** bind-mounts its content/media from the source tree so the admin
  editor writes back to your working copy. Runs Astro in dev mode (its current
  Dockerfile).
- **entrypoint** is built static and served by nginx; its Vite `base` is
  overridden to `/` at build time (it defaults to `/entrypoint-v2/` for GitHub
  Pages).
- `make clean` removes volumes and **destroys app data** — use with care.
