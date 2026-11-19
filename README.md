# Varun’s Personal HQ

A local-first dashboard for projects, tasks, milestones and a flexible daily routine. Open [the new life system](life-system/index.html) in a browser. Tasks and completion state are stored in that browser’s local storage on this device.

The consolidated dashboard, complete task snapshot, planning notes and dated history are in [`life-system/`](life-system/README.md). It is also the default dashboard on GitHub Pages. Task edits remain browser-local until backed up or exported. The repository is public, so keep personal profile content, customer records, health data, identity documents, credentials, and business/tax identifiers out of committed files.

## Current focus areas

- Career move targeted for February 2027: resume, role direction, LinkedIn, Naukri, Indeed, Cutshort and discovery of other relevant portals; verify each portal's current onboarding and privacy rules before creating profiles.
- Dairy farm planning targeted for January 2027: start with 20 animals and preserve a path to 40; compare shed construction, solar and CCTV proposals.
- CareerScope, AI World 360 Media daily publishing on YouTube and Instagram, ValueMela, and personal health/routine.
- Other desktop projects and responsibilities are listed for status review: OraOne, the Godavari dairy guide, Family, FixHub24, LensMate, Training & learning, and Life admin.

Most seeded tasks are **Not started**; two preliminary supplier-research items are **In progress** and explicitly lack vendor contact, quotes or verification. Project percentages now count only tasks marked **Done**, divided by all tasks in that area; in-progress and waiting work do not inflate the completion percentage. Seeded statuses are planning estimates and are not evidence of completed work.

## Edit and privacy

Use **Add a task** and the status dropdowns in the dashboard. When the local dashboard opens, it now merges newly seeded tasks and categories into existing browser data while preserving recorded task statuses. Use **Backup** to download a JSON copy and **Restore** to load it on this device. Task and habit data still lives in this browser’s local storage; the backup file is the way to carry data between devices. The initial task set can be edited in the page’s `seed` data. No credentials, resume contents, or account tokens belong in this repository. This repository is public. All tracked files, task snapshots and Git history are visible to anyone. Keep personal details, customer data, contact information, credentials and government identifiers out of it.

Local browser edits do not sync to GitHub automatically. Syncing exports and pushes the review snapshot plus a sanitized task-only feed (`life-system/tasks.json` and `life-system/data.js`) into this public repository. The Pages dashboard can load the latest synced task feed. Review exports and keep personal or sensitive details out. The repository is `https://github.com/varunjakkampudi-tech/personal-hq`.

## Next setup steps

1. Confirm the current resume, target roles, geography and job-search constraints.
2. Capture farm location, utilities, land/site constraints, budget and decision maker.
3. Add existing project priorities and authorized next steps.
4. Tailor workout and food planning after goals, schedule, preferences and relevant health constraints are known.
5. Set a workable daily YouTube/Instagram production routine and review the final asset before each post or schedule activation.

## Personal health starter

General, non-personalized routine guidance and the information needed to tailor it are in [research/health-routine-starter.md](research/health-routine-starter.md). No calorie, weight, supplement, or intensive exercise plan is assumed.

## Career transition preparation

The February 2027 role-change plan uses the blank, private intake and verification workbook in [research/career-transition-workbook.md](research/career-transition-workbook.md). It covers verified chronology, achievement evidence, role constraints, resume review gates and portal privacy checks. Do not commit completed personal values, the resume, credentials or OTPs to this repo or to public Pages.

Profile updates and public posts should be reviewed by Varun before submission or publication.

## AI World 360 daily publishing

The daily YouTube/Instagram checklist and per-video record template are in [research/ai-world-360-daily-workflow.md](research/ai-world-360-daily-workflow.md). This workflow is not evidence of channel access or completed uploads; each day's final exports and publication URLs must be recorded. A specific scheduled draft requires its own approval.

## Dairy farm supplier research

The preliminary West Godavari solar, CCTV and shed-contractor shortlist, sources and quote checklist are in [research/supplier-shortlist-west-godavari.md](research/supplier-shortlist-west-godavari.md). Candidates are not endorsements; no vendor has been contacted or verified.

The phased 20-to-40-animal site, operating, compliance and commissioning gates are in [research/dairy-farm-readiness.md](research/dairy-farm-readiness.md). January 2027 remains a conditional target until the site, species, market and local requirements are verified.


## ValueMela GST planning

The review-first GST checklist is in [research/valuemela-gst-registration.md](research/valuemela-gst-registration.md). It distinguishes questions to resolve from documents that must remain private. No GST application has been filed.


## Task registry for daily review

`private/task-registry.json` is the local machine-readable snapshot used by the daily review when available. It must remain untracked; the folder name does not provide access control on a shared machine. A prior version was mistakenly committed, so older copies remain in public Git history. The current branch removes the file; this change does not rewrite that history. The dashboard stores browser edits locally. After changing task statuses, choose **Export tasks**. A local Windows task checks Downloads every 15 minutes and after sign-in, validates the fresh export with `tools/sync-task-registry.ps1`, keeps a pre-sync backup when the registry changes, and updates the local registry. It publishes only sanitized task fields to `life-system/tasks.json` and `life-system/data.js`; it does not publish habits, habit logs, life-log entries or the full export. A local marker skips an already-synced export; if a push fails, the watcher retries on a later run. The Pages dashboard can load the latest published task snapshot with **Load latest tasks**. The watcher ignores missing, stale or unsupported exports. Its log is `%LOCALAPPDATA%\Personal-HQ\sync-automation.log` and does not include task content. Run the helper with `pwsh -NoProfile -File .\tools\sync-task-registry.ps1`; remove the watcher with `Unregister-ScheduledTask -TaskName 'Personal HQ task export sync' -Confirm:$false`. The daily review must report when the snapshot is stale or unavailable.

The sync helper refuses an export that omits any task ID already in the registry. Before syncing from the public Pages dashboard, restore a complete backup from this desktop dashboard so the public browser has the full task list; this prevents an empty or partial template from replacing existing work.

Task records include an owner, source and next action. Dates and completion states are only meaningful when you update them from evidence. The initial registry is a starter copy of the dashboard seed, not proof that any task has been completed. It is marked as unreconciled until replaced by an **Export tasks** snapshot. Current exports include `registryStatus: current-user-export`. The sync helper rejects common Aadhaar, PAN, GSTIN, email-address and Indian phone-number patterns before publishing; this is a basic filter and not a guarantee that an export contains no sensitive information.
