-- Histagram schema (already applied to the Supabase project). Tables are prefixed hg_.

create table public.hg_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_.]{3,24}$'),
  display_name text not null default '' check (char_length(display_name) <= 60),
  bio text not null default '' check (char_length(bio) <= 150),
  avatar_path text,
  created_at timestamptz not null default now()
);

create table public.hg_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.hg_profiles(id) on delete cascade,
  image_path text not null,
  caption text not null default '' check (char_length(caption) <= 2200),
  created_at timestamptz not null default now()
);
create index hg_posts_user_idx on public.hg_posts(user_id, created_at desc);
create index hg_posts_created_idx on public.hg_posts(created_at desc);

create table public.hg_likes (
  post_id uuid not null references public.hg_posts(id) on delete cascade,
  user_id uuid not null references public.hg_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index hg_likes_user_idx on public.hg_likes(user_id);

create table public.hg_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.hg_posts(id) on delete cascade,
  user_id uuid not null references public.hg_profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index hg_comments_post_idx on public.hg_comments(post_id, created_at);
create index hg_comments_user_idx on public.hg_comments(user_id);

create table public.hg_follows (
  follower_id uuid not null references public.hg_profiles(id) on delete cascade,
  following_id uuid not null references public.hg_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);
create index hg_follows_following_idx on public.hg_follows(following_id);

alter table public.hg_profiles enable row level security;
alter table public.hg_posts enable row level security;
alter table public.hg_likes enable row level security;
alter table public.hg_comments enable row level security;
alter table public.hg_follows enable row level security;

create policy hg_profiles_select on public.hg_profiles for select to authenticated using (true);
create policy hg_profiles_update on public.hg_profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy hg_posts_select on public.hg_posts for select to authenticated using (true);
create policy hg_posts_insert on public.hg_posts for insert to authenticated
  with check (user_id = (select auth.uid()) and image_path like (select auth.uid())::text || '/%');
create policy hg_posts_delete on public.hg_posts for delete to authenticated
  using (user_id = (select auth.uid()));

create policy hg_likes_select on public.hg_likes for select to authenticated using (true);
create policy hg_likes_insert on public.hg_likes for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy hg_likes_delete on public.hg_likes for delete to authenticated
  using (user_id = (select auth.uid()));

create policy hg_comments_select on public.hg_comments for select to authenticated using (true);
create policy hg_comments_insert on public.hg_comments for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy hg_comments_delete on public.hg_comments for delete to authenticated
  using (user_id = (select auth.uid())
         or exists (select 1 from public.hg_posts p where p.id = hg_comments.post_id and p.user_id = (select auth.uid())));

create policy hg_follows_select on public.hg_follows for select to authenticated using (true);
create policy hg_follows_insert on public.hg_follows for insert to authenticated
  with check (follower_id = (select auth.uid()));
create policy hg_follows_delete on public.hg_follows for delete to authenticated
  using (follower_id = (select auth.uid()));

create function public.hg_ensure_profile() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  u record;
  base text;
  uname text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if exists (select 1 from public.hg_profiles where id = me) then return; end if;
  select email, raw_user_meta_data as meta into u from auth.users where id = me;
  base := lower(regexp_replace(coalesce(u.meta->>'username', split_part(u.email, '@', 1), 'user'), '[^a-zA-Z0-9_.]', '', 'g'));
  if char_length(base) < 3 then base := base || 'user'; end if;
  base := left(base, 24);
  uname := base;
  while exists (select 1 from public.hg_profiles where username = uname) loop
    uname := left(base, 19) || (floor(random() * 9000) + 1000)::int::text;
  end loop;
  insert into public.hg_profiles (id, username, display_name)
  values (me, uname, left(coalesce(u.meta->>'name', ''), 60));
end $$;
revoke execute on function public.hg_ensure_profile() from public, anon;
grant execute on function public.hg_ensure_profile() to authenticated;

create function public.hg_feed(p_scope text default 'following', p_limit int default 30, p_before timestamptz default null)
returns table (id uuid, user_id uuid, username text, avatar_path text, image_path text, caption text,
               created_at timestamptz, like_count bigint, comment_count bigint, liked_by_me boolean)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.user_id, pr.username, pr.avatar_path, p.image_path, p.caption, p.created_at,
    (select count(*) from public.hg_likes l where l.post_id = p.id),
    (select count(*) from public.hg_comments c where c.post_id = p.id),
    exists (select 1 from public.hg_likes l where l.post_id = p.id and l.user_id = auth.uid())
  from public.hg_posts p
  join public.hg_profiles pr on pr.id = p.user_id
  where (p_before is null or p.created_at < p_before)
    and (p_scope = 'explore'
         or p.user_id = auth.uid()
         or p.user_id in (select f.following_id from public.hg_follows f where f.follower_id = auth.uid()))
  order by p.created_at desc
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.hg_get_post(p_id uuid)
returns table (id uuid, user_id uuid, username text, avatar_path text, image_path text, caption text,
               created_at timestamptz, like_count bigint, comment_count bigint, liked_by_me boolean)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.user_id, pr.username, pr.avatar_path, p.image_path, p.caption, p.created_at,
    (select count(*) from public.hg_likes l where l.post_id = p.id),
    (select count(*) from public.hg_comments c where c.post_id = p.id),
    exists (select 1 from public.hg_likes l where l.post_id = p.id and l.user_id = auth.uid())
  from public.hg_posts p
  join public.hg_profiles pr on pr.id = p.user_id
  where p.id = p_id;
$$;

create function public.hg_profile_stats(p_user uuid)
returns table (post_count bigint, follower_count bigint, following_count bigint, is_following boolean)
language sql stable security invoker set search_path = '' as $$
  select (select count(*) from public.hg_posts where user_id = p_user),
         (select count(*) from public.hg_follows where following_id = p_user),
         (select count(*) from public.hg_follows where follower_id = p_user),
         exists (select 1 from public.hg_follows where following_id = p_user and follower_id = auth.uid());
$$;

revoke execute on function public.hg_feed(text, int, timestamptz) from public, anon;
revoke execute on function public.hg_get_post(uuid) from public, anon;
revoke execute on function public.hg_profile_stats(uuid) from public, anon;
grant execute on function public.hg_feed(text, int, timestamptz) to authenticated;
grant execute on function public.hg_get_post(uuid) to authenticated;
grant execute on function public.hg_profile_stats(uuid) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hg-media', 'hg-media', false, 10485760,
        array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif'])
on conflict (id) do nothing;

create policy hg_media_select on storage.objects for select to authenticated
  using (bucket_id = 'hg-media');
create policy hg_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'hg-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy hg_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'hg-media' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ================= Reels =================
create table if not exists public.hg_reels (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.hg_profiles(id) on delete cascade,
  video_path text not null,
  caption text not null default '',
  duration_ms integer not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.hg_reel_likes (
  reel_id uuid not null references public.hg_reels(id) on delete cascade,
  user_id uuid not null references public.hg_profiles(id) on delete cascade,
  primary key (reel_id, user_id)
);
create table if not exists public.hg_reel_comments (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.hg_reels(id) on delete cascade,
  user_id uuid not null references public.hg_profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
-- RLS: everyone signed in can read; you can add/remove your own; a reel's
-- owner can also delete comments on it. Private bucket 'hg-reels' (50 MB,
-- video only), uploads only into the folder named after your user id.
-- Feed function used by the app: hg_reels_feed(p_limit, p_before)
