-- English + Spanish word filter for titles, notes, meet-up spots and names (SPEC §7.6, B3).
-- Words are stored lowercase without accents and match whole words, plus a plural "s"/"es".
-- Add more with: insert into private.blocked_words (word) values ('...');

create extension if not exists unaccent with schema extensions;

create table private.blocked_words (
    word text primary key check (word ~ '^[a-z]+$')
);
revoke all on private.blocked_words from public, anon, authenticated;

insert into private.blocked_words (word) values
    -- English
    ('fuck'), ('fucker'), ('fucking'), ('motherfucker'), ('shit'), ('bullshit'), ('bitch'), ('cunt'),
    ('asshole'), ('bastard'), ('whore'), ('slut'), ('cock'), ('pussy'), ('porn'), ('rape'), ('rapist'),
    ('nigger'), ('nigga'), ('faggot'), ('fag'), ('retard'), ('retarded'), ('kys'),
    -- Spanish (Mexico first)
    ('puta'), ('puto'), ('putazo'), ('pendejo'), ('pendeja'), ('pendejada'), ('verga'), ('chingar'),
    ('chinga'), ('chingada'), ('chingado'), ('cabron'), ('cabrona'), ('culero'), ('culera'), ('culo'),
    ('mamon'), ('mamona'), ('mamada'), ('pinche'), ('ojete'), ('panocha'), ('mierda'), ('zorra'),
    ('perra'), ('joto'), ('maricon'), ('marica'), ('mayate'), ('gilipollas')
on conflict do nothing;

-- Trims, enforces the length limit and rejects links, mass mentions and blocked words.
-- Parameters: the raw text, its limit after trimming, and whether it may be empty.
-- Returns the trimmed text, or null for empty optional text. Raises invalid_text.
create or replace function private.clean_text(p_value text, p_limit integer, p_required boolean default false)
returns text language plpgsql stable security definer set search_path = ''
as $$
declare
    v_clean text := nullif(btrim(p_value), '');
    v_folded text;
begin
    if (p_required and v_clean is null) or char_length(coalesce(v_clean, '')) > p_limit
       or coalesce(v_clean, '') ~* '(https?://|www\.|@everyone|@here)' then
        raise exception 'invalid_text';
    end if;
    if v_clean is not null then
        v_folded := lower(extensions.unaccent(v_clean));
        if exists (select 1 from private.blocked_words w where v_folded ~ ('\m' || w.word || '(e?s)?\M')) then
            raise exception 'invalid_text';
        end if;
    end if;
    return v_clean;
end $$;

revoke execute on function private.clean_text(text, integer, boolean) from public, anon, authenticated;
