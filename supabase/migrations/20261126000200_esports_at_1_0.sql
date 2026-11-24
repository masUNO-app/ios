-- Esports is gated to 1.0, the release after 0.9, not "0.10" (20261126000000). There is no 0.10, so
-- nothing changes for any build; this only makes the gate say what it means.
update public.activity_kinds set min_app_version = '1.0' where slug = 'esports';
update public.activities set min_app_version = '1.0' where kind = 'esports';
