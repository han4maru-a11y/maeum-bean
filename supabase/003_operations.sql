-- REFERENCE ONLY. Replace placeholders, then run selected statements as project owner.
-- Do not execute this entire file blindly.
-- 1) Approve an actual teacher after verifying identity and school authorization:
-- update public.profiles set approved=true where id='TEACHER_UUID' and role='teacher';
-- 2) Inspect pending teachers:
select id,nickname,organization,created_at from public.profiles where role='teacher' and not approved;
-- 3) View deletion requests. Delete auth user via Supabase Auth Admin console after verification.
-- For teachers: first reassign classroom ownership / resolve counseling data retention.
select d.student_id,p.nickname,d.created_at from public.deletion_requests d join public.profiles p on p.id=d.student_id;
-- 4) Future beans use updated target. Existing beans retain their target snapshot.
-- update public.operation_settings set growth_target=40,retention_days=365 where id=true;
-- 5) Retention dry run (do not delete without school-specific retention policy and procedures):
select count(*) as expired_records from public.mood_records where created_at<now()-make_interval(days=>(select retention_days from public.operation_settings));
-- 6) Optional test-only water provision, NEVER expose this as client RPC:
-- insert into public.water_transactions(student_id,amount,reason,reference)
-- values('STUDENT_UUID',30,'테스트 전용 지급','test-seed-001');
-- 7) Student class transfer: verify both schools/classes, prevent previous teacher access,
-- and decide how earlier school records and counseling notes should be migrated/deleted.
-- Membership migration is intentionally NOT exposed to the student.
-- 8) Data access/write audit (server-side):
select * from public.audit_logs order by created_at desc limit 100;
