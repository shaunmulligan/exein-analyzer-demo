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

`balena build` builds `homeassistant` and pulls `browser`. `balena deploy`
then pushes both local images without a second pull.

Add a service to `docker-compose.yml` and the workflow scans it too. There is
no service list to keep in the workflow.

## How the gate works

Exein CVE analysis can take hours, so the pipeline does not wait for it.
A balena draft release holds each build until its scans pass. The fleet's
"track latest" policy ignores drafts, so devices never get an ungated release.

`build-scan-deploy.yml` runs on every push to `main`:

1. `build` runs `balena build`, then saves one tarball per compose service
   (`scripts/compose-images.sh`).
2. `scan` runs once per service. It finds or creates the Analyzer object
   `<repo>-<service>` (`scripts/exein-object.sh`), then uploads the tarball
   with [`exein-io/analyzer-scan`](https://github.com/exein-io/analyzer-scan).
3. `deploy` loads the tarballs and runs `balena deploy --draft`. The release
   gets the tags `exein-scan-<service>=<scan-id>` and `exein-gate=pending`.

`exein-gate.yml` runs about every 15 minutes, at :07, :22, :37 and :52
(`scripts/release-gate.sh`):

1. It finds drafts tagged `exein-gate=pending`, oldest first.
2. If a draft's scans are still running, it stops, so releases finalize in
   build order.
3. When the scans finish, it downloads each VEX and PDF report and counts
   CVEs at or above `FAIL_ON` (default `critical`). It skips CVEs that Exein
   marks `not_affected`, `false_positive`, or `resolved`
   (`scripts/exein-gate.sh`).
4. It attaches the VEX and report files to the release as release assets.
5. It tags the release with the result:

   | Result | `exein-gate` | Release |
   |---|---|---|
   | No blocking CVEs | `pass` | Finalized; devices update |
   | Blocking CVEs | `fail` | Stays a draft |
   | Blocking CVEs, `enforce` cleared | `override` | Finalized |
   | Scan failed in Exein | `error` | Stays a draft |

   `exein-blocking` holds the count, and `exein-fail-on` holds the threshold.

To gate right away, or to show the override path, run **Actions → Exein
gate → Run workflow**. Clear `enforce` to finalize failing drafts as
`override`.

## Setup

1. Create a balenaCloud fleet for `raspberrypi5`.
2. In the GitHub repo settings, add:

   | Kind | Name | Value |
   |---|---|---|
   | Secret | `ANALYZER_API_KEY` | Exein Analyzer API key |
   | Secret | `BALENA_TOKEN` | balenaCloud API key |
   | Variable | `BALENA_FLEET` | Fleet slug, for example `myorg/exein-ha-demo` |

   You do not create Analyzer objects. Each `scan` job finds the object
   `<repo>-<service>` by name, for example
   `exein-analyzer-demo-homeassistant`, and creates it if it does not exist.

3. Push to `main`. When the scans finish, run **Exein gate** with `enforce`
   cleared to finalize the first release.
4. Complete the Home Assistant onboarding once from a laptop at
   `http://<device-ip>:8123`. The `ha-storage` volume keeps the user.
   After that, the kiosk logs in with no password through `trusted_networks`
   (127.0.0.1 only).

The workflow runs on `ubuntu-24.04-arm`, so it builds natively with no QEMU.

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

## Test the gate locally

```sh
test/gate-test.sh
```

The test runs the gate against fixture VEX files. It checks the pass and
block cases for both `FAIL_ON` levels.

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
