---
name: apple-container
description: "Use when working with Apple's `container` CLI on macOS (container run/build/exec/image/system/builder/volume/network, Containerfile or Dockerfile builds on Apple silicon) and whenever container work must be pinned to arm64/aarch64. Covers forcing linux/arm64 everywhere, catching silent amd64 fallback, disabling Rosetta, and verifying image architecture. Trigger keywords: apple container, container run, container build, container system start, CONTAINER_DEFAULT_PLATFORM, macOS container, Apple silicon container, arm64, aarch64, arm64/v8, Rosetta, multi-arch image, platform mismatch. Do not use for Docker Desktop, colima, podman, or Kubernetes."
---

# Apple Container, pinned to arm64

Apple's `container` is a macOS-native container runtime. Each container gets its
own lightweight VM. It is **not** Docker: no `docker` compatibility layer and no
daemon socket. It has its own `container compose` with only `up` and `down`.
Flags overlap with Docker but diverge — check `container <cmd> --help` before
assuming a flag exists. Verify the installed version with
`container system version`.

## The arch naming that trips everyone up

Three names for the same thing. Use the right one in the right place:

| Where | Correct token | Notes |
| --- | --- | --- |
| OCI platform string (`--platform`) | `linux/arm64` | Normalizes to `linux/arm64/v8` |
| `--arch` flag, image config | `arm64` | This is the CLI/OCI arch name |
| Inside the Linux guest (`uname -m`) | `aarch64` | Kernel's name for the same ISA |
| macOS host (`uname -m`) | `arm64` | Darwin's name |

`aarch64` is accepted as an alias and normalizes to `arm64`: `--arch aarch64`
and `--platform linux/aarch64` both work. Still prefer the canonical `arm64`
spelling, so what you write matches what `image inspect` reports back.

`--platform` takes precedence over `--os` and `--arch`. Prefer `--platform`
and never mix the two forms in one command.

## Force arm64 globally

Set the env var once. It is read natively by `run`, `build`, `image pull`, and
`image push`:

```sh
export CONTAINER_DEFAULT_PLATFORM=linux/arm64
```

Put it in `~/.zshrc` so every shell and every subprocess inherits it. When it
takes effect, `container run` prints a confirming line:

```
using platform from environment variable: ["variable": CONTAINER_DEFAULT_PLATFORM, "platform": linux/arm64]
```

If that line is absent, the env var is not reaching the CLI — fix that before
trusting anything else.

Belt and braces, pass the flag explicitly in scripts and CI, where the
environment is not yours to control:

```sh
container build   --platform linux/arm64 -t app:local .
container run     --platform linux/arm64 --rm app:local
container image pull --platform linux/arm64 alpine:latest
container image push --platform linux/arm64 registry.example.com/app:1.0
```

## The silent amd64 trap

`container` will pull and run x86_64 images **without warning or error**:

```sh
container image pull --platform linux/amd64 alpine:latest   # succeeds
container run --platform linux/amd64 --rm alpine uname -m   # prints x86_64
```

There is no "exec format error" to alert you. An amd64 image runs under
emulation and is merely slow and subtly different. Assume nothing; verify.

Multi-arch tags make this worse: a single local image reference can hold both
an `amd64` and an `arm64` variant. `container image ls` shows one row and one
digest either way, so the listing cannot tell you what you have.

## Verify, don't assume

Check which variants a local image actually contains:

```sh
container image inspect <image> | jq -r '.[0].variants[].config.architecture'
```

A correctly pinned build prints exactly `arm64` and nothing else. Two lines
(`amd64` and `arm64`) means an amd64 variant is present and reachable.

Assert it in a build script or CI step:

```sh
archs=$(container image inspect "$IMAGE" | jq -r '.[0].variants[].config.architecture' | sort -u)
[ "$archs" = "arm64" ] || { echo "FAIL: expected arm64 only, got: $archs" >&2; exit 1; }
```

Confirm at runtime from inside the guest — expect `aarch64` here, not `arm64`:

```sh
container run --rm "$IMAGE" uname -m
```

## Rosetta

`container system property ls` shows `rosetta = true` under `[build]` by
default. Rosetta is what lets amd64 content run at all, which is exactly the
failure mode you are trying to make loud. For an arm64-only workflow:

- Turn it off for the builder in `~/.config/container/config.toml`, then
  restart the services (`container system stop && container system start`;
  the file is read only at startup):

  ```toml
  [build]
  rosetta = false
  ```

- Never pass `--rosetta` to `container run` or `container create`.
- Never pass more than one `--arch` to `container build`
  (`--arch arm64 --arch amd64` builds a multi-arch image on purpose).
- Treat any need for Rosetta as a bug in your image selection, not a solution.
- Confirm the effective settings with `container system property ls`. There is
  no `property set` subcommand; `config.toml` is the only way to change them.

## Base images must be arm64-capable

Pinning `--platform` only helps if the base image publishes an arm64 variant.
Before adopting a base image:

```sh
container image pull --platform linux/arm64 <base>
container image inspect <base> | jq -r '.[0].variants[].config.architecture'
```

In a Containerfile, do not hardcode x86 artifacts. Select by arch instead:

```dockerfile
FROM alpine:latest
RUN arch="$(uname -m)" \
 && case "$arch" in aarch64) ;; *) echo "unsupported arch: $arch" >&2; exit 1 ;; esac
```

The `case` guard fails the build loudly if the base resolved to x86_64, which
is far better than shipping a silently emulated image.

## Command reference

Real subcommands as of CLI 1.6.1. Both `container <group> <sub> --help` and
`container help <group> <sub>` work.

### Lifecycle

```sh
container system start        # start services; required before anything else
container system status
container system stop
container system version
container system df           # disk usage
container system property ls  # effective config (config.toml + defaults)
container system logs [-f] [--last 10m]
container system dns create|delete|ls <domain>   # create/delete need sudo
container system kernel set --recommended
```

### Containers

```sh
container run [opts] <image> [args]
container create / start / stop / kill / delete / prune
container exec -it <id> <cmd>
container ls [-a] [-q] [--format json|table|yaml|toml]
container logs [-f] [-n N] [--boot] <id>
container inspect <id>
container stats [--no-stream] [--format json]
container cp <src> <id>:<dst>       # alias of `container copy`
container commit <id> <image:tag>   # snapshot a container into an image
container export [-o file.tar] <id>
container clean <id>                # reclaim free space in a running container
```

Useful `run` flags: `--rm`, `-d`, `-i`, `-t`, `-e KEY=VAL`, `--env-file`,
`-v <host>:<guest>`, `--mount type=,source=,target=,readonly`, `-p <h>:<c>`,
`-w <dir>`, `-u <user>`, `-c <cpus>`, `-m <mem>`, `--name`, `--network`,
`--entrypoint`, `--init`, `--read-only`, `--tmpfs`, `--shm-size`, `--ssh`,
`--cap-add` / `--cap-drop`, `--ulimit`, `--dns`.

### Images

```sh
container build --platform linux/arm64 -f Containerfile -t app:local .
container image ls / inspect / delete / prune
container image pull  --platform linux/arm64 <ref>
container image push  --platform linux/arm64 <ref>
container image tag <src> <dst>
container image save --platform linux/arm64 -o app.tar <ref>
container image load -i app.tar
container registry login [-u <user> --password-stdin] <host>
container registry logout <host> / ls
```

`build` also takes `--build-arg`, `--secret id=<key>[,env=|,src=]`, `--target`,
`--no-cache`, `--pull`, `--ssh default`, `--output type=oci|tar|local[,dest=]`,
`-c/--cpus`, `-m/--memory`. Without `-f` it looks for `Dockerfile`, then
`Containerfile`.

### Builder, volumes, networks

```sh
container builder start [-c <cpus>] [-m <mem>] [--dns <ip>]
container builder status / stop / delete

container volume create [-s <size>] [--opt journal=ordered] <name>
container volume ls / inspect / delete / prune

container network create [--subnet <cidr>] [--internal] <name>   # macOS 26+
container network ls / inspect / delete / prune
```

The builder is a container itself. If builds fail oddly after an upgrade, or
hang, restart it: `container builder stop && container builder start`.

### Compose, machines, clusters

```sh
container compose up / down [-v]    # only these two subcommands
container machine create --name dev --cpus 4 --memory 8G <image>
container machine run -n dev [-- cmd]   # persistent Linux dev VM, home mounted rw by default
container machine ls / set / stop / delete
container cluster create            # EXPERIMENTAL local Kubernetes (kind node image)
```

`machine create` and `cluster create` honor `--platform` and
`CONTAINER_DEFAULT_PLATFORM` too; check their images the same way.

## Resource sizing

Defaults are small: 4 CPUs / 1 GiB per container and 2 CPUs / 2 GiB for the
builder (see `container system property ls`). For anything compute-heavy —
compiling, running test suites — size up explicitly with `-c`/`-m` on
`run`/`build`, or `-c`/`-m` on `container builder start`. 4 CPUs / 4GB RAM is a
reasonable floor for those workflows; bump further if builds or tests still
thrash. To change the defaults persistently, set `[container]` and `[build]`
`cpus`/`memory` in `~/.config/container/config.toml` and restart the services.

## Troubleshooting

- **"Plugin 'container-<x> <y>' not found"** — usually means services are down.
  Run `container system start`.
- **Build cannot resolve DNS** — the builder has its own DNS config. Pass
  `--dns` to `container builder start`, not just to `build`.
- **Image runs but behaves oddly / slowly** — check for an amd64 variant with
  the `image inspect` command above.
- **Bind mounts** — `container` maps host paths into a per-container VM. Expect
  different performance and permission behavior than Docker Desktop; prefer
  named volumes for write-heavy workloads.

## Checklist for arm64-only work

1. `export CONTAINER_DEFAULT_PLATFORM=linux/arm64` in the shell profile.
2. Pass `--platform linux/arm64` explicitly in every script and CI invocation.
3. Confirm the base image publishes arm64 before adopting it.
4. Guard the Containerfile with an `aarch64` check.
5. Assert `image inspect` reports `arm64` and only `arm64`.
6. Set `[build] rosetta = false` in `~/.config/container/config.toml`.
7. Never pass `--rosetta`; treat needing it as a defect.
