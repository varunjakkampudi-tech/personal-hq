# Varun’s Personal HQ

A local-first dashboard for projects, tasks, milestones and a flexible daily routine. Open `index.html` in a browser. Tasks and completion state are stored in that browser’s local storage on this device.

## Current focus areas

- Career move targeted for February 2027: resume, role direction, LinkedIn, Naukri, Indeed, Cutshort and other relevant profiles.
- Dairy farm planning targeted for January 2027: start with 20 animals and preserve a path to 40; compare shed construction, solar and CCTV proposals.
- CareerScope, AI World 360 Media (YouTube and Instagram), ValueMela, and personal health/routine.
- Other desktop projects and responsibilities are listed for status review: OraOne, the Godavari dairy guide, Family, FixHub24, LensMate, Training & learning, and Life admin.

Most seeded tasks are **Not started**; two preliminary supplier-research items are **In progress** and explicitly lack vendor contact, quotes or verification. Project progress weights Done as 100%, In progress as 50%, Waiting as 25% and Not started as 0%. Seeded statuses are planning estimates and are not evidence of completed work.

## Edit and privacy

Use **Add a task** and the status dropdowns in the dashboard. Use **Backup** to download a JSON copy and **Restore** to load it on this device. Task and habit data still lives in this browser’s local storage; the backup file is the way to carry data between devices. The initial task set can be edited in the page’s `seed` data. No credentials, resume contents, or account tokens belong in this repository. Do not put private personal details here if you intend to publish the repository publicly.

Local browser edits do not sync to GitHub automatically. Sync the dashboard export into the private registry file and push the update when needed. The private repository is `https://github.com/varunjakkampudi-tech/personal-hq`; GitHub Pages is a separate public generic template.

## Next setup steps

1. Confirm the current resume, target roles, geography and job-search constraints.
2. Capture farm location, utilities, land/site constraints, budget and decision maker.
3. Add existing project priorities and authorized next steps.
4. Tailor workout and food planning after goals, schedule, preferences and relevant health constraints are known.
5. Agree a sustainable YouTube/Instagram publishing cadence and review workflow.

Profile updates and public posts should be reviewed by Varun before submission or publication.

## Dairy farm supplier research

The preliminary West Godavari solar, CCTV and shed-contractor shortlist, sources and quote checklist are in [research/supplier-shortlist-west-godavari.md](research/supplier-shortlist-west-godavari.md). Candidates are not endorsements; no vendor has been contacted or verified.


## ValueMela GST planning

The review-first GST checklist is in [research/valuemela-gst-registration.md](research/valuemela-gst-registration.md). It distinguishes questions to resolve from documents that must remain private. No GST application has been filed.


## Private task registry for daily review

`private/task-registry.json` is the private, machine-readable task snapshot used by the daily review when available. It is committed only in this private GitHub repository and must never be copied to the public Pages repository. The dashboard itself still uses browser local storage. After changing task statuses, choose **Sync tasks** and replace `private/task-registry.json` with the downloaded dated JSON export. The daily review must state that reconciliation is pending if this snapshot is stale or unavailable. Do not put the private registry in the public Pages repository.

Task records include an owner, source and next action. Dates and completion states are only meaningful when you update them from evidence. The initial registry is a starter copy of the dashboard seed, not proof that any task has been completed. It is marked as unreconciled until replaced by a Sync tasks export. Current exports include `registryStatus: current-user-export`.
