/*
=============================================================
Create Data Warehouse Schemas — PostgreSQL
=============================================================
Script Purpose:
    This script creates three schemas in the currently
    connected PostgreSQL database:
        1. bronze — stores raw source data.
        2. silver — stores cleaned and transformed data.
        3. gold   — stores business-ready data for analysis.

Prerequisite:
    Connect to the 'SQL_Data_Warehouse' database in SQLTools
    before running this script.

Notes:
    - Existing schemas are preserved.
    - No database, tables, or data are deleted.
    - This script can be run again safely.
=============================================================
*/

-- ==========================================================
-- Check the currently connected database
-- Expected result: SQL_Data_Warehouse
-- ==========================================================
SELECT current_database();


-- ==========================================================
-- Create the Bronze Schema
-- Purpose: Store raw data imported from source systems
-- ==========================================================
CREATE SCHEMA IF NOT EXISTS bronze;


-- ==========================================================
-- Create the Silver Schema
-- Purpose: Store cleaned, standardised, and transformed data
-- ==========================================================
CREATE SCHEMA IF NOT EXISTS silver;


-- ==========================================================
-- Create the Gold Schema
-- Purpose: Store business-ready tables and reporting views
-- ==========================================================
CREATE SCHEMA IF NOT EXISTS gold;


-- ==========================================================
-- Verify that all three schemas exist
-- ==========================================================
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('bronze', 'silver', 'gold')
ORDER BY schema_name;