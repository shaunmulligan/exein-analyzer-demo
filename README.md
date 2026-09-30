# Exein + balena supply-chain demo

A Home Assistant kiosk on a Raspberry Pi 5. Every release goes through
[Exein Analyzer](https://www.exein.io/platform/exein-analyzer) before it
reaches the fleet:

```text
balena build  ->  docker save  ->  Exein scan  ->  CVE gate  ->  balena deploy
```

`balena deploy` pushes the images that `balena build` made on the same
runner. The images Exein scans are the images that ship.

## What runs on the device

| Service | Image | Role |
|---|---|---|
| `homeassistant` | `ghcr.io/home-assistant/home-assistant:2026.9.4` (digest-pinned) | HA with the `demo` integration and a YAML dashboard |
| `browser` | `bh.cr/balenalabs/browser-aarch64/2.12.0` | Chromium kiosk that shows the dashboard |

`balena build` builds `homeassistant` and pulls `browser`. `balena deploy`
then pushes both local images without a second pull.

## The gate

The [`exein-io/analyzer-scan`](https://github.com/exein-io/analyzer-scan)
action uploads each image and returns a scan ID. It does not gate on results.
This repo adds the gate:

1. `scripts/exein-fetch.sh` waits for each scan, then downloads the PDF report
   and the VEX document (CycloneDX with `vulnerabilities[]`).
2. `scripts/exein-gate.sh` counts CVEs with a high or critical rating.
   It skips CVEs that Exein marks `not_affected`, `false_positive`, or
   `resolved`.
3. If the count is not zero, the job fails and `balena deploy` does not run.

The job summary lists the counts per service and links to each scan.
The report and VEX files are workflow artifacts.

Push to `main` always enforces the gate. A manual run
(**Actions → Build, scan, deploy → Run workflow**) has an `enforce` checkbox.
Clear it to deploy regardless and show the warning path.

## Setup

1. Create a balenaCloud fleet for `raspberrypi5`.
2. Create one Analyzer object per service and note the IDs:

   ```sh
   analyzer object new exein-demo-homeassistant
   analyzer object new exein-demo-browser
   ```

3. In the GitHub repo settings, add:

   | Kind | Name | Value |
   |---|---|---|
   | Secret | `ANALYZER_API_KEY` | Exein Analyzer API key |
   | Secret | `BALENA_TOKEN` | balenaCloud API key |
   | Variable | `BALENA_FLEET` | Fleet slug, for example `myorg/exein-ha-demo` |
   | Variable | `EXEIN_OBJECT_HA` | Object ID for `homeassistant` |
   | Variable | `EXEIN_OBJECT_BROWSER` | Object ID for `browser` |

4. Run the workflow with `enforce` cleared for the first release.
5. Complete the Home Assistant onboarding once from a laptop at
   `http://<device-ip>:8123`. The `ha-storage` volume keeps the user.
   After that, the kiosk logs in with no password through `trusted_networks`
   (127.0.0.1 only).

The workflow runs on `ubuntu-24.04-arm`, so it builds natively with no QEMU.
Arm runners are free for public repos only.

## Demo script

1. Show the dashboard on the Pi.
2. Run the workflow with `enforce` set. Show the gate fail, the job summary,
   and the Exein scan pages. Run `balena releases <fleet>` to show that no new
   release exists.
3. Run the workflow with `enforce` cleared. Show the release in balenaCloud
   with the `exein-scan-*` release tags that link it to its scans.

## Test the gate locally

```sh
test/gate-test.sh
```

The test runs the gate against fixture VEX files. It checks the pass, block,
and non-enforced cases.

## Known limits

- The upstream HA and Chromium images carry high and critical CVEs, so the
  enforced gate fails on current releases. That is the "blocked" demo path.
- The fixture VEX files follow CycloneDX 1.6. Confirm the filter against a
  real Exein VEX download before a live demo.
- Config changes ship with each release. HA history (`home-assistant_v2.db`)
  resets when the container restarts.

---

Co-authored with Claude
