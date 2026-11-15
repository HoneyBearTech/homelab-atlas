# Plan: triage the open Trivy alerts (#108)

## What was asked

"start work on #108": every open image-scan alert is fixed by an image update or dismissed with its reason, and
`docs/dependencies.md` has the new counts and the date.

## What we found

- The weekly scan of `main` (15 November 2026) has **468 open Trivy alerts** (22 critical, 444 high, 2 medium). They
  come from 86 advisories in 23 groups of the same package with the same answer. Each pinned image was scanned again
  with the same Trivy version and flags as `scan.yml`, and the counts match code scanning exactly.
- **20 are fixed by updates that already exist**: a rebuild of Sonarr 4.0.20.3014 with newer krb5 and libxslt
  packages (19 alerts) and Dozzle v11.4.3 (1). Renovate proposes the Sonarr rebuild on Monday, 16 November, and
  Dozzle v11.4.3 on Monday, 23 November, once its three-day wait is over. No newer
  stable image exists for Radarr, Lidarr, Bazarr, SABnzbd, Recyclarr or Seerr.
- **114 are not reachable in this stack**, each for a specific reason checked against the image's contents and the
  app's source: server-side code the apps never run (Kerberos KDC, OAuth 2 endpoints, S/MIME verification), copies
  of a library that nothing calls (two old nodemailer copies in Seerr, the npm tool in its base image), and features
  the apps don't use (TIFF encoding in Radarr's and Sonarr's ImageSharp, git merge in Recyclarr, an HTTPS proxy
  in Bazarr and SABnzbd).
- **334 are plausibly reachable and have no fix yet**:
  - 292 in the .NET 8 runtime bundled in Radarr and Lidarr. .NET 8 went out of support on 10 November 2026.
  - 7 in Sonarr's .NET 6 runtime, out of support since 2024.
  - 30 in ImageSharp's TIFF support: 18 in the decoder, which decodes posters from metadata servers, and 12 in
    the TIFF encoders in Lidarr, which re-encode a `.tif` cover as TIFF.
  - 5 in Bazarr and SABnzbd (certifi, soupsieve, urllib3).

  Only the apps' prerelease lines move off .NET 8: Radarr 7 and Sonarr 5, both on .NET 10. Lidarr has no release
  that does.

## What we'll change

1. **Updates.** Let Renovate bring the Sonarr rebuild (Monday, 16 November) and Dozzle v11.4.3 (Monday,
   23 November; on the 16th it may offer v11.4.2, which doesn't fix the alert), after the smoke test, as usual, so
   the team doesn't open pull requests that duplicate Renovate's. The Dozzle hub on the other host has to move to
   v11.4.3 too (the agent stays on the hub's version). *Check:* after 23 November, both pins are on `main`,
   and the next scan closes the 20 alerts.
2. **The findings in `docs/dependencies.md`.** A dated "Current findings" section (anchor `#current-findings`,
   which the October dismissals and #108 link to and which no longer exists). It gives the counts, and one row per
   group: what fixes it, why it is or isn't reachable, and the mitigation for the ones kept open: LAN only,
   logins on, trusted indexers and subtitle providers only, and any reverse proxy must reject ambiguous requests.
   It records the end-of-support .NET runtimes, and corrects the October PyJWT wording (oauthlib does import it, on
   demand, for RSA signing and RS256 tokens). *Check:* lint, the counts add up to 468, and every dismissal text
   matches a row.
3. **The roadmap.** New items: move Radarr and Sonarr to their .NET 10 releases once those are stable, and watch
   Lidarr's; dismiss the ImageSharp TIFF alerts once a stable release limits the decoders and encoders; bind
   the published ports to a configurable host address; memory limits; start Seerr without npm's update check.
   *Check:* review.
4. **Dismiss the 114 alerts** in code scanning, as "won't fix" with the group's reason (at most 280 characters,
   each linking `docs/dependencies.md#current-findings`), like the October dismissals. This is done only after the
   final approval, under the owner's account: the automation app has no access to code scanning. *Check:* the
   open count drops by exactly 114, and every dismissed alert carries its text. The six October PyJWT
   dismissals get the corrected comment.
5. **Keep the 334 open**, rather than dismissing them as the issue's "done" asks. They are plausibly reachable, so
   dismissing them would hide a real risk. They close as the apps ship fixes.

Docs only: no image or Compose change, and no effect on the server.

## Who's on it

Researcher (done: the triage above), Engineer (the docs), QA (counts, links, lint), Security Officer and an
independent Auditor (each checks every "not reachable" reason against its advisory and the app's code, and that
nothing reachable is being dismissed).

## Risks

- A wrong "not reachable" call hides a real risk. Each reason is checked twice, independently. Dismissed alerts
  can be reopened, and the doc says what would make each one reachable (for example, setting a proxy for Bazarr).
- The kept-open .NET findings are the real exposure, and nothing in this repository can fix them. The mitigations
  limit who can reach the apps. They don't remove the bugs.

## Out of scope

Running prerelease Radarr 7 or Sonarr 5; the 4 Scorecard alerts; replacing autoheal (#109).
