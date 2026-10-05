-- 旅ナビ：場所の金額（円）
-- 003_plan_coords.sql のあとに、Supabase の SQL Editor で1回だけ実行する。
-- （食事・外せない移動・宿泊の金額は、旅ごとの日程（trip_plans.plan の中身）に入るので、新しい表はいらない）

alter table public.spots
  add column cost integer check (cost is null or (cost >= 0 and cost < 100000000));
