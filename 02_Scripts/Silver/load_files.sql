/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Purpose:
    Replace silver table contents with cleaned bronze data.

Usage:
    CALL silver.load_silver();

Assumptions:
    - Bronze sales date columns contain integers in YYYYMMDD format.
    - Eight-digit date values represent valid calendar dates.
    - All target tables and columns already exist.
===============================================================================
*/

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    start_time       TIMESTAMPTZ;
    batch_start_time TIMESTAMPTZ;
BEGIN
    batch_start_time := clock_timestamp();

    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Silver Layer';
    RAISE NOTICE '================================================';

    RAISE NOTICE 'Loading CRM Tables';

    -- ========================================================================
    -- 1. CRM Customer Information
    -- ========================================================================

    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.crm_cust_info';
    TRUNCATE TABLE silver.crm_cust_info;

    RAISE NOTICE '>> Inserting Data Into: silver.crm_cust_info';

    INSERT INTO silver.crm_cust_info (
        cst_id,
        cst_key,
        cst_firstname,
        cst_lastname,
        cst_marital_status,
        cst_gndr,
        cst_create_date
    )
    SELECT
        cst_id,
        cst_key,
        TRIM(cst_firstname) AS cst_firstname,
        TRIM(cst_lastname) AS cst_lastname,

        CASE UPPER(TRIM(cst_marital_status))
            WHEN 'S' THEN 'Single'
            WHEN 'M' THEN 'Married'
            ELSE 'n/a'
        END AS cst_marital_status,

        CASE UPPER(TRIM(cst_gndr))
            WHEN 'F' THEN 'Female'
            WHEN 'M' THEN 'Male'
            ELSE 'n/a'
        END AS cst_gndr,

        CAST(cst_create_date AS DATE) AS cst_create_date

    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY cst_id
                ORDER BY cst_create_date DESC NULLS LAST
            ) AS flag_last
        FROM bronze.crm_cust_info
        WHERE cst_id IS NOT NULL
    ) AS t
    WHERE flag_last = 1;

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RAISE NOTICE '>> -------------';

    -- ========================================================================
    -- 2. CRM Product Information
    -- ========================================================================

    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.crm_prd_info';
    TRUNCATE TABLE silver.crm_prd_info;

    RAISE NOTICE '>> Inserting Data Into: silver.crm_prd_info';

    INSERT INTO silver.crm_prd_info (
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        prd_end_dt
    )
    SELECT
        prd_id,

        REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,

        SUBSTRING(prd_key FROM 7) AS prd_key,

        prd_nm,

        COALESCE(prd_cost, 0) AS prd_cost,

        CASE UPPER(TRIM(prd_line))
            WHEN 'M' THEN 'Mountain'
            WHEN 'R' THEN 'Road'
            WHEN 'S' THEN 'Other Sales'
            WHEN 'T' THEN 'Touring'
            ELSE 'n/a'
        END AS prd_line,

        CAST(prd_start_dt AS DATE) AS prd_start_dt,

        CAST(
            LEAD(prd_start_dt) OVER (
                PARTITION BY prd_key
                ORDER BY prd_start_dt
            ) AS DATE
        ) - 1 AS prd_end_dt

    FROM bronze.crm_prd_info;

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RAISE NOTICE '>> -------------';

    -- ========================================================================
    -- 3. CRM Sales Details
    -- ========================================================================

    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.crm_sales_details';
    TRUNCATE TABLE silver.crm_sales_details;

    RAISE NOTICE '>> Inserting Data Into: silver.crm_sales_details';

    INSERT INTO silver.crm_sales_details (
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        sls_sales,
        sls_quantity,
        sls_price
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,

        CASE
            WHEN sls_order_dt IS NULL
                 OR sls_order_dt <= 0
                 OR LENGTH(sls_order_dt::TEXT) != 8
            THEN NULL
            ELSE TO_DATE(sls_order_dt::TEXT, 'YYYYMMDD')
        END AS sls_order_dt,

        CASE
            WHEN sls_ship_dt IS NULL
                 OR sls_ship_dt <= 0
                 OR LENGTH(sls_ship_dt::TEXT) != 8
            THEN NULL
            ELSE TO_DATE(sls_ship_dt::TEXT, 'YYYYMMDD')
        END AS sls_ship_dt,

        CASE
            WHEN sls_due_dt IS NULL
                 OR sls_due_dt <= 0
                 OR LENGTH(sls_due_dt::TEXT) != 8
            THEN NULL
            ELSE TO_DATE(sls_due_dt::TEXT, 'YYYYMMDD')
        END AS sls_due_dt,

        -- Recalculate missing, nonpositive, or inconsistent sales.
        CASE
            WHEN sls_sales IS NULL
                 OR sls_sales <= 0
                 OR sls_sales != sls_quantity * ABS(sls_price)
            THEN sls_quantity * ABS(sls_price)
            ELSE sls_sales
        END AS sls_sales,

        sls_quantity,

        -- Derive price using original bronze sales and quantity.
        CASE
            WHEN sls_price IS NULL OR sls_price <= 0
            THEN sls_sales::NUMERIC / NULLIF(sls_quantity, 0)
            ELSE sls_price
        END AS sls_price

    FROM bronze.crm_sales_details;

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RAISE NOTICE '>> -------------';

    RAISE NOTICE 'Loading ERP Tables';

    -- ========================================================================
    -- 4. ERP Customer Information
    -- ========================================================================

    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.erp_cust_az12';
    TRUNCATE TABLE silver.erp_cust_az12;

    RAISE NOTICE '>> Inserting Data Into: silver.erp_cust_az12';

    INSERT INTO silver.erp_cust_az12 (
        cid,
        bdate,
        gen
    )
    SELECT
        CASE
            WHEN cid LIKE 'NAS%'
            THEN SUBSTRING(cid FROM 4)
            ELSE cid
        END AS cid,

        -- Birthdates after today are invalid.
        CASE
            WHEN CAST(bdate AS DATE) > CURRENT_DATE
            THEN NULL
            ELSE CAST(bdate AS DATE)
        END AS bdate,

        CASE
            WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE')
            THEN 'Female'
            WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')
            THEN 'Male'
            ELSE 'n/a'
        END AS gen

    FROM bronze.erp_cust_az12;

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RAISE NOTICE '>> -------------';

    -- ========================================================================
    -- 5. ERP Customer Locations
    -- ========================================================================

    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.erp_loc_a101';
    TRUNCATE TABLE silver.erp_loc_a101;

    RAISE NOTICE '>> Inserting Data Into: silver.erp_loc_a101';

    INSERT INTO silver.erp_loc_a101 (
        cid,
        cntry
    )
    SELECT
        REPLACE(cid, '-', '') AS cid,

        CASE
            WHEN TRIM(cntry) = 'DE'
            THEN 'Germany'
            WHEN TRIM(cntry) IN ('US', 'USA')
            THEN 'United States'
            WHEN TRIM(cntry) = '' OR cntry IS NULL
            THEN 'n/a'
            ELSE TRIM(cntry)
        END AS cntry

    FROM bronze.erp_loc_a101;

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RAISE NOTICE '>> -------------';

    -- ========================================================================
    -- 6. ERP Product Categories
    -- ========================================================================

    start_time := clock_timestamp();

    RAISE NOTICE '>> Truncating Table: silver.erp_px_cat_g1v2';
    TRUNCATE TABLE silver.erp_px_cat_g1v2;

    RAISE NOTICE '>> Inserting Data Into: silver.erp_px_cat_g1v2';

    INSERT INTO silver.erp_px_cat_g1v2 (
        id,
        cat,
        subcat,
        maintenance
    )
    SELECT
        id,
        cat,
        subcat,
        maintenance
    FROM bronze.erp_px_cat_g1v2;

    RAISE NOTICE '>> Load Duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RAISE NOTICE '>> -------------';

    -- ========================================================================
    -- Completion
    -- ========================================================================

    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Silver Layer is Completed';
    RAISE NOTICE 'Total Load Duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time));
    RAISE NOTICE '================================================';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '================================================';
        RAISE NOTICE 'ERROR OCCURRED DURING LOADING SILVER LAYER';
        RAISE NOTICE 'Error Message: %', SQLERRM;
        RAISE NOTICE 'SQLSTATE: %', SQLSTATE;
        RAISE NOTICE '================================================';

        -- Propagate the error so the caller knows the load failed.
        RAISE;
END;
$$;