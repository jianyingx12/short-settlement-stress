CREATE OR REPLACE FUNCTION market_structure.symbol_match_key(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
RETURNS NULL ON NULL INPUT
AS $$
    SELECT nullif(
        upper(
            regexp_replace(
                replace(btrim(value), 'p', 'PR'),
                '[^A-Za-z0-9]',
                '',
                'g'
            )
        ),
        ''
    );
$$;

CREATE OR REPLACE FUNCTION market_structure.issuer_name_match_key(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
RETURNS NULL ON NULL INPUT
AS $$
    SELECT nullif(
        btrim(upper(regexp_replace(value, '[^A-Za-z0-9]+', ' ', 'g'))),
        ''
    );
$$;

CREATE OR REPLACE FUNCTION market_structure.cusip_is_valid(value text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
RETURNS NULL ON NULL INPUT
AS $$
DECLARE
    normalized text := upper(btrim(value));
    character text;
    character_value integer;
    weighted_value integer;
    checksum_total integer := 0;
    position integer;
BEGIN
    IF normalized !~ '^[0-9A-Z*@#]{8}[0-9]$' THEN
        RETURN false;
    END IF;

    FOR position IN 1..8 LOOP
        character := substr(normalized, position, 1);
        character_value := CASE
            WHEN character BETWEEN '0' AND '9' THEN ascii(character) - ascii('0')
            WHEN character BETWEEN 'A' AND 'Z' THEN ascii(character) - ascii('A') + 10
            WHEN character = '*' THEN 36
            WHEN character = '@' THEN 37
            WHEN character = '#' THEN 38
        END;
        weighted_value := character_value * CASE WHEN position % 2 = 0 THEN 2 ELSE 1 END;
        checksum_total := checksum_total + weighted_value / 10 + weighted_value % 10;
    END LOOP;

    RETURN right(normalized, 1)::integer = (10 - checksum_total % 10) % 10;
END;
$$;

COMMENT ON FUNCTION market_structure.symbol_match_key(text) IS
    'Comparison key only. Expands the FINRA lowercase p preferred-share marker to PR; it is not a permanent security identifier.';
