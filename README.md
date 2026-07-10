# homelab

Single repo that runs and manages self-hosted apps in containers, each on its
own `*.localhost` domain, behind one reverse proxy. Adding an app is a small
YAML file; rolling out a new version is one command.

## Layout

```
homelab/
├── compose.yaml        # proxy (traefik) + include: list of apps + shared network
├── traefik.yaml        # proxy static config (routing is auto via labels)
├── Makefile            # up / down / rollout / logs helpers
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

[Traefik](https://traefik.io) watches the docker socket. Any container labeled
`traefik.enable=true` with a `Host(...)` rule gets routed automatically — no
proxy config edits per app. `*.localhost` already resolves to loopback on Linux
and in browsers, so `http://ouioui.localhost` hits Traefik on `:80`, which
forwards to the ouioui container.

Traefik dashboard: http://localhost:8080

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

| App        | URL                        |
|------------|----------------------------|
| entrypoint | http://entrypoint.localhost |
| kashkul    | http://kashkul.localhost   |
| ouioui     | http://ouioui.localhost    |

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
   dir) and the container `PORT`.
3. Add `- apps/myapp.yaml` to the `include:` list in `compose.yaml`.
4. `make rollout app=myapp` → live at `http://myapp.localhost`.

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
