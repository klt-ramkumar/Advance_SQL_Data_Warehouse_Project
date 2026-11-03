SET client_min_messages = NOTICE;

DO $$
BEGIN
    RAISE NOTICE 'Testing notice messages';
END;
$$;