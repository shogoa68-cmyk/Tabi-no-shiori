-- 旅ナビ：日程と拠点（宿）、場所の位置（緯度・経度）
-- 002_share.sql のあとに、Supabase の SQL Editor で1回だけ実行する。

-- 場所の位置（住所から調べた緯度・経度。わからないときは空）
alter table public.spots
  add column lat double precision check (lat between -90 and 90),
  add column lng double precision check (lng between -180 and 180);

-- 旅ごとの日程と拠点（開始日・終了日・日ごとの朝と夜の拠点）。中身は画面が作る JSON をそのまま入れる
create table public.trip_plans (
  trip_id     uuid primary key references public.trips(id) on delete cascade,
  plan        jsonb not null default '{}'::jsonb check (pg_column_size(plan) < 100000),
  updated_at  timestamptz not null default now()
);
create trigger trip_plans_touch before update on public.trip_plans for each row execute function public.touch_updated_at();

alter table public.trip_plans enable row level security;
create policy "trip_plans: メンバーは見られる" on public.trip_plans for select to authenticated
  using (public.is_trip_member(trip_id));
create policy "trip_plans: メンバーは作れる" on public.trip_plans for insert to authenticated
  with check (public.is_trip_member(trip_id));
create policy "trip_plans: メンバーは直せる" on public.trip_plans for update to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));

revoke all on public.trip_plans from anon;
grant select, insert, update on public.trip_plans to authenticated;
