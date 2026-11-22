-- 마음콩 공유 동의 및 기록 접근 보완 패치
-- 적용 조건: 기존 001_schema.sql을 새 Supabase 프로젝트에 성공적으로 실행한 직후 실행
-- 이 파일은 001_schema.sql을 대체하지 않습니다.
-- 학생의 기본 기록/테마 기록 동의를 분리하고, 마음 일기는 항상 본인만 열람하도록 합니다.

begin;

-- 1) 승인된 담당 교사 여부를 더 엄격하게 확인
create or replace function public.teaches(s uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.classroom_members m
    join public.classrooms c on c.id = m.classroom_id
    join public.profiles p on p.id = c.teacher_id
    where m.student_id = s
      and c.teacher_id = auth.uid()
      and p.role = 'teacher'
      and p.approved = true
  )
$$;

create or replace function public.owns_class(c uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.classrooms x
    join public.profiles p on p.id = x.teacher_id
    where x.id = c
      and x.teacher_id = auth.uid()
      and p.role = 'teacher'
      and p.approved = true
  )
$$;

-- 2) 기본 기록과 테마 기록의 동의 상태를 분리
alter table public.sharing_preferences
  add column if not exists basic_consent_confirmed boolean not null default false,
  add column if not exists theme_shared boolean not null default false,
  add column if not exists theme_consent_confirmed boolean not null default false;

-- 기존 basic 동의값은 새 기본 동의 칼럼으로 옮김
update public.sharing_preferences
set basic_consent_confirmed = consent_confirmed
where consent_confirmed = true;

-- 기존 테마 공유는 별도 동의를 받은 기록인지 확인할 수 없으므로 기본 비공유로 시작
update public.sharing_preferences
set theme_shared = false,
    theme_consent_confirmed = false;

-- 3) 예전의 단일 동의 함수는 제거하고, 종류별 동의 함수로 교체
revoke all on function public.set_sharing(boolean, boolean) from public, anon, authenticated;
drop function public.set_sharing(boolean, boolean);

create function public.set_sharing(
  p_kind text,
  p_shared boolean,
  p_consent boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s uuid := public.require_student();
begin
  if p_kind not in ('basic', 'theme') then
    raise exception '공유 기록 종류가 올바르지 않습니다';
  end if;

  if p_shared and not p_consent then
    raise exception '공유하려면 해당 기록 종류의 동의가 필요합니다';
  end if;

  if p_kind = 'basic' then
    update public.sharing_preferences
    set basic_shared = p_shared,
        basic_consent_confirmed = p_consent,
        consent_confirmed = p_consent,
        updated_at = now()
    where student_id = s;
  else
    update public.sharing_preferences
    set theme_shared = p_shared,
        theme_consent_confirmed = p_consent,
        updated_at = now()
    where student_id = s;
  end if;

  insert into public.audit_logs(actor, action, entity)
  values (s, 'sharing_changed', p_kind);
end
$$;

revoke all on function public.set_sharing(text, boolean, boolean) from public, anon, authenticated;
grant execute on function public.set_sharing(text, boolean, boolean) to authenticated;

-- 4) 교사 본인이 담당하는 학생의 '공유된 기록'만 읽을 수 있는 RLS 보조 함수
-- 이 함수는 임의 학생의 동의 여부를 노출하지 않으며, 현재 로그인한 교사가
-- 해당 학생의 승인된 담당 교사이고 기록 종류별 동의가 유효한 경우에만 true를 반환합니다.
create or replace function public.can_view_shared_mood(
  p_student uuid,
  p_kind text,
  p_shared boolean
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(p_shared, false)
    and p_kind in ('basic', 'theme')
    and public.teaches(p_student)
    and exists (
      select 1
      from public.sharing_preferences sp
      where sp.student_id = p_student
        and (
          (p_kind = 'basic'
            and sp.basic_shared = true
            and sp.basic_consent_confirmed = true)
          or
          (p_kind = 'theme'
            and sp.theme_shared = true
            and sp.theme_consent_confirmed = true)
        )
    )
$$;

revoke all on function public.can_view_shared_mood(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.can_view_shared_mood(uuid, text, boolean) to authenticated;

drop policy if exists records_read on public.mood_records;

-- 예전 함수는 동의 여부를 임의 학생 UUID로 조회할 수 있어 제거
revoke all on function public.basic_is_shared(uuid) from public, anon, authenticated;
drop function public.basic_is_shared(uuid);

-- 5) 기존 기록 조회 정책을 새 동의 구조로 교체
drop policy if exists records_read on public.mood_records;

create policy records_read
on public.mood_records
for select
to authenticated
using (
  student_id = auth.uid()
  or public.can_view_shared_mood(student_id, kind, shared)
);

-- 6) 기록 저장 함수: 공유 선택은 해당 종류의 동의가 있을 때만 허용
create or replace function public.save_record(
  p_kind text,
  p_question_id text,
  p_answer text,
  p_shared boolean default false
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  s uuid := public.require_student();
  d date := (now() at time zone 'Asia/Seoul')::date;
  q public.daily_questions;
  expected text;
  old public.mood_records;
  v int := 0;
  can_share boolean := false;
begin
  if p_answer is null or length(trim(p_answer)) < 1 or length(trim(p_answer)) > 3000 then
    raise exception '기록은 1자 이상 3000자 이하로 입력하세요';
  end if;

  if p_kind = 'diary' then
    if p_shared then
      raise exception '마음 일기는 다른 사람과 공유할 수 없습니다';
    end if;

    insert into public.mood_records(
      student_id, kind, category, question, answer, shared
    )
    values (
      s, 'diary', '일기', '나만의 마음 일기', trim(p_answer), false
    );
    return 0;
  end if;

  if p_kind not in ('basic', 'theme') then
    raise exception '기록 종류 오류';
  end if;

  select *
  into q
  from public.daily_questions
  where id = p_question_id
    and active = true;

  if q.id is null then
    raise exception '유효한 질문이 아닙니다';
  end if;

  if p_kind = 'basic' then
    select id
    into expected
    from public.daily_questions
    where weekday = extract(dow from d)::int
      and active
      and category <> '테마'
    order by id
    offset (
      (d - date '2026-01-01')
      % greatest(
          1,
          (
            select count(*)::int
            from public.daily_questions
            where weekday = extract(dow from d)::int
              and active
              and category <> '테마'
          )
        )
    )
    limit 1;

    if q.id <> expected then
      raise exception '오늘의 질문을 다시 불러오세요';
    end if;
  elsif p_kind = 'theme' then
    if q.category <> '테마' then
      raise exception '테마 질문만 선택할 수 있습니다';
    end if;
  end if;

  if jsonb_typeof(q.options) = 'array'
     and jsonb_array_length(q.options) > 0
     and not (q.options ? p_answer) then
    raise exception '선택지를 확인하세요';
  end if;

  if p_shared then
    if p_kind = 'basic' then
      select (basic_shared and basic_consent_confirmed)
      into can_share
      from public.sharing_preferences
      where student_id = s;
    else
      select (theme_shared and theme_consent_confirmed)
      into can_share
      from public.sharing_preferences
      where student_id = s;
    end if;

    if coalesce(can_share, false) = false then
      raise exception '이 기록 종류의 공유 동의를 먼저 설정하세요';
    end if;
  end if;

  select *
  into old
  from public.mood_records
  where student_id = s
    and record_date = d
    and kind = p_kind
    and (p_kind = 'basic' or question_id = p_question_id);

  if old.id is null then
    v := case
      when p_kind = 'basic' then 1
      else least(5, greatest(1, right(q.id, 1)::int))
    end;

    insert into public.mood_records(
      student_id, kind, category, question_id, question,
      answer, shared, reward
    )
    values (
      s, p_kind, q.category, q.id, q.prompt,
      trim(p_answer), coalesce(p_shared, false), v
    );

    insert into public.water_transactions(
      student_id, amount, reason, reference
    )
    values (
      s,
      v,
      '마음 기록',
      p_kind || ':' || d || ':' ||
        case when p_kind = 'basic' then 'daily' else q.id end
    );
  else
    update public.mood_records
    set answer = trim(p_answer),
        shared = coalesce(p_shared, false),
        updated_at = now()
    where id = old.id;
  end if;

  insert into public.audit_logs(actor, action, entity)
  values (s, 'record_saved', p_kind);

  return v;
end
$$;

-- 7) 새 함수의 실행 권한을 명시적으로 제한
-- save_record는 기존 allowlist 권한을 유지하지만 다시 명시해 둡니다.
revoke all on function public.save_record(text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.save_record(text, text, text, boolean) to authenticated;

commit;
