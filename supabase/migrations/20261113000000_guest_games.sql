-- Guest browsing (1.0, SPEC R7-15): someone who hasn't signed in can look at a campus's open games
-- before making an account. A guest sees each game's sport, title, time, duration, place and how
-- many are going, with room left. Names stay with verified students (SPEC §8.8): no host or
-- attendee, no host's note, no meet-up spot and no chat. Joining, saving and hosting still need an
-- account, so nothing per-viewer comes back either.
--
-- This is the only game read `anon` has. `game_cards`, `games` and `rsvps` stay closed to it: a
-- function that returns just these columns is easier to keep private than column grants and an
-- `anon` policy on tables that also hold names.

-- Open games on one campus, as a guest sees them: the same rows the map shows a student there (not
-- cancelled, ended or full, starting within 7 days), newest bump first. Only a campus that Find
-- your school lists (`university_lookup`, so never the hidden demo campus) and that's open to new
-- sign-ups; any other campus returns nothing. Like `game_cards`, a banned host's games still show.
-- Parameters: the campus.
-- Returns one row per game, with no names, notes or meet-up spot.
create function public.guest_games(p_university uuid)
returns table (
    id uuid,
    activity_slug text,
    title text,
    starts_at timestamptz,
    duration_minutes integer,
    ends_at timestamptz,
    capacity integer,
    going_count integer,
    spots_left integer,
    place_name text,
    place_address text,
    lat double precision,
    lng double precision,
    reposted_at timestamptz,
    created_at timestamptz,
    sort_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
    select g.id, g.activity_slug, g.title, g.starts_at, g.duration_minutes, g.ends_at,
           g.capacity, g.going_count, g.capacity - g.going_count, g.place_name, g.place_address,
           g.lat, g.lng, g.reposted_at, g.created_at, coalesce(g.reposted_at, g.created_at)
    from public.games g
    join public.universities u on u.id = g.university_id
    where g.university_id = p_university
      and not u.is_demo
      and u.signup_enabled
      and g.cancelled_at is null
      and g.ends_at > now()
      and g.starts_at < now() + interval '7 days'
      and g.going_count < g.capacity
    order by coalesce(g.reposted_at, g.created_at) desc
$$;

revoke execute on function public.guest_games(uuid) from public;
grant execute on function public.guest_games(uuid) to anon, authenticated;
