# Private Personal HQ sync database

This folder defines a proposed Supabase/Postgres schema for authenticated private task storage. It is source-controlled because it contains schema only; private task data, resume/GST/health records, project credentials and service-role keys must never be committed.

The migration is not applied to a live project. Before doing so, create/select the owner's Supabase project, choose a region and plan, review retention and costs, then verify the migration in a disposable project. The static GitHub Pages app is not connected yet.

The first migration creates owner-scoped task, habit, habit-log and life-log tables. RLS policies use `auth.uid()`. Only authenticated access is granted. Task saves and soft deletes are compare-and-swap operations using an expected revision. A stale write returns no row and must be presented as a conflict. Task deletion is recoverable through a later write with the current tombstone revision.

Do not consider the system ready for live data until two-user RLS isolation, wrong-revision behavior, restore/recovery, offline handling, browser-to-browser sync, and privacy scans of the built Pages files are verified. Habit and life-log writes also need a client-side sync/conflict design before those tables become an active shared source.
