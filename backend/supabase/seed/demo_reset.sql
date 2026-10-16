-- Removes all demo data created by demo.sql (accounts *@demo.reefish.app, zones "Demo %", their trips' load)
-- and republishes the heatmap. Safe on a project with real users: only demo rows are touched.
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/demo_reset.sql
begin;
select private.demo_reset();
commit;
