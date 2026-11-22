-- Read-only configuration checks. Run in SQL Editor as owner after 001/002.
-- These inspect setup, NOT an end-to-end acceptance test.
select tablename,rowsecurity from pg_tables where schemaname='public' order by tablename;
select tablename,policyname,cmd from pg_policies where schemaname='public' order by tablename;
select tablename from pg_publication_tables where pubname='supabase_realtime' and schemaname='public';
select category,count(*) from public.daily_questions group by category order by category;
select proname,prosecdef from pg_proc where pronamespace='public'::regnamespace order by proname;
-- Sensitive helpers must NOT be exposed:
select has_function_privilege('authenticated','public.balance(uuid)','EXECUTE') as must_be_false,
 has_function_privilege('authenticated','public.require_student()','EXECUTE') as also_false;
-- Direct writes must be denied:
select has_table_privilege('authenticated','public.water_transactions','INSERT') as must_be_false,
 has_table_privilege('authenticated','public.profiles','UPDATE') as also_false;
-- Use three independent browser profiles to perform the full tests in ACCEPTANCE.md.
