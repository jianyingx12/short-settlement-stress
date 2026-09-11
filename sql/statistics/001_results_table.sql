DROP TABLE IF EXISTS market_structure.statistical_results;

CREATE TABLE market_structure.statistical_results (
    result_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    research_question text NOT NULL,
    analysis_name text NOT NULL,
    sample text NOT NULL,
    observation_count bigint NOT NULL,
    estimate_name text NOT NULL,
    estimate double precision,
    confidence_low double precision,
    confidence_high double precision,
    p_value double precision,
    effect_size_name text,
    effect_size double precision,
    method text NOT NULL,
    notes text,
    UNIQUE (research_question, analysis_name, sample, estimate_name)
);

COMMENT ON TABLE market_structure.statistical_results IS
    'Statistical results for the four research questions.';
