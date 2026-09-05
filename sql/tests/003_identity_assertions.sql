DO $$
BEGIN
    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.short_volume_daily
        WHERE identity_status <> 'MATCHED' AND security_id IS NOT NULL
    ), 'uncertain short-volume identities received a security ID';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.short_volume_daily
        WHERE symbol_normalization_collision
          AND (identity_status <> 'AMBIGUOUS' OR security_id IS NOT NULL)
    ), 'normalization collisions were forced into an identity';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.short_interest_observation
        WHERE identity_status <> 'MATCHED' AND security_id IS NOT NULL
    ), 'uncertain short-interest identities received a security ID';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.security_symbol_range AS first_range
        JOIN market_structure.security_symbol_range AS second_range
          ON second_range.symbol_match_key = first_range.symbol_match_key
         AND second_range.evidence_from <= first_range.evidence_to
         AND second_range.evidence_to >= first_range.evidence_from
         AND second_range.evidence_from <> first_range.evidence_from
    ), 'symbol evidence ranges overlap';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM market_structure.security_symbol_range
        WHERE mapping_status <> 'MATCHED' AND security_id IS NOT NULL
    ), 'ambiguous or unresolved ranges received a security ID';
END;
$$;
