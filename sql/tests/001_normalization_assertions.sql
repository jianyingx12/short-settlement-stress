DO $$
BEGIN
    ASSERT market_structure.symbol_match_key('ABCpA') = 'ABCPRA',
        'preferred-share comparison key failed';
    ASSERT market_structure.symbol_match_key('ABCw') = 'ABCW',
        'warrant comparison key failed';
    ASSERT market_structure.symbol_match_key('ABCr') = 'ABCR',
        'rights comparison key failed';
    ASSERT market_structure.symbol_match_key(' BRK.B ') = 'BRKB',
        'punctuation normalization failed';
    ASSERT market_structure.symbol_match_key('   ') IS NULL,
        'blank symbols should normalize to NULL';
    ASSERT market_structure.cusip_is_valid('037833100'),
        'valid CUSIP was rejected';
    ASSERT NOT market_structure.cusip_is_valid('037833101'),
        'invalid CUSIP checksum was accepted';
END;
$$;
