# Exein + balena supply-chain demo

A Home Assistant kiosk on a Raspberry Pi 5. Every release is scanned by
[Exein Analyzer](https://www.exein.io/platform/exein-analyzer), and devices
only get a release after it passes the scan:

```text
build -> Exein upload -> balena draft release -> (scans finish) -> CVE gate -> finalize
```

The workflow saves each image as a tarball. Exein scans the tarball, and the
deploy job loads that same tarball. The images Exein scans are the images
that ship.

## What runs on the device

| Service | Image | Role |
|---|---|---|
| `homeassistant` | `ghcr.io/home-assistant/home-assistant:2026.9.4` (digest-pinned) | HA with the `demo` integration and a YAML dashboard |
| `browser` | `bh.cr/balenalabs/browser-aarch64/2.12.0` | Chromium kiosk that shows the dashboard |

`browser/Dockerfile.template` picks the block for the fleet's arch with
`%%BALENA_ARCH%%`, so one compose file builds for the Pi 5 and x86 fleets.

## Fleets

This repo deploys one app to two fleets, listed in both workflow files:

| Fleet | Device | Arch | Build |
|---|---|---|---|
| Pi 5 fleet | Raspberry Pi 5 | `aarch64` | native on `ubuntu-24.04-arm` |
| `exein_analyzer_demo_x86` | x86 | `amd64` | native on `ubuntu-24.04` |

To add a fleet, add its slug to `fleets` in
`.github/workflows/build-scan-deploy.yml` and `.github/workflows/exein-gate.yml`.

The single-container Pi 3 (`armv7hf`) example is
[exein-analyzer-demo-single](https://github.com/shaunmulligan/exein-analyzer-demo-single).

## How the gate works

The pipeline is the [balena-exein](https://github.com/shaunmulligan/balena-exein)
reusable workflows. This repo only calls them:

- `build-scan-deploy.yml`, on every push to `main`: builds each fleet, uploads
  every image to Exein, and deploys a draft release tagged
  `exein-gate=pending`. Devices ignore drafts.
- `exein-gate.yml`, about every 15 minutes: when a draft's scans finish, it
  gates the draft on critical CVEs, attaches the VEX and PDF reports, and
  finalizes it only on `pass` (or `override`).

See the balena-exein README for the inputs, tags, and security notes.

## Setup

1. Create the balenaCloud fleets: `raspberrypi5` and an x86 type such as
   `generic-amd64`.
2. Put both fleet slugs in `fleets` in the two files in `.github/workflows/`
   (replace `PI5_FLEET_SLUG` and `X86_FLEET_SLUG`).
3. In the GitHub repo settings, add the secrets `ANALYZER_API_KEY` (Exein
   Analyzer API key) and `BALENA_TOKEN` (balenaCloud API key).

   You do not create Analyzer objects. The pipeline finds the object
   `<fleet-name>-<service>`, for example
   `exein_analyzer_demo_x86-homeassistant`, and creates it if it does not
   exist.

4. Push to `main`. When the scans finish, run **Exein gate** with `enforce`
   cleared to finalize the first release.
5. Complete the Home Assistant onboarding once from a laptop at
   `http://<device-ip>:8123`. The `ha-storage` volume keeps the user.
   After that, the kiosk logs in with no password through `trusted_networks`
   (127.0.0.1 only).

## Demo script

Scans take hours, so push before the demo.

1. Show the dashboard on the Pi.
2. Show a push in **Build, scan, deploy draft**: images uploaded to Exein and
   a draft release tagged `exein-gate=pending`. The device stays on its
   current release.
3. Show **Exein gate** on that release: the summary table, the
   `exein-gate=fail` tag, and the VEX and report attached in the balenaCloud
   dashboard.
4. Run **Exein gate** with `enforce` cleared. The release finalizes as
   `override`, and the Pi updates.

## Known limits

- The upstream HA and Chromium images carry critical CVEs (317 at 2026.9.4 and
  2.12.0), so the enforced gate fails on current releases. That is the
  "blocked" demo path.
- Exein CVE analysis took 3–5 hours for these images, and over 20 minutes for
  a 4 MB Alpine image.
- GitHub can start scheduled runs late, and disables them in a public repo
  after 60 days with no activity.
- Config changes ship with each release. HA history (`home-assistant_v2.db`)
  resets when the container restarts.

---

Co-authored with Claude
