# PostgreSQL Data Warehouse | Medallion Architecture

A SQL data warehouse that brings CRM and ERP sales data together using **Medallion Architecture: Bronze, Silver, and Gold layers**. Six source CSV files are loaded into PostgreSQL, cleaned with SQL, and exposed through a dimensional model for customer, product, and sales analysis.

Built by **Ram Kannan** as a hands-on data engineering project, adapting a SQL Server learning workflow to PostgreSQL.

[Setup guide](04_Setup/README.md) · [SQL scripts](03_Scripts/) · [Datasets](01_datasets/) · [Project documentation](02_docs/)

## Project overview

The project demonstrates an end-to-end batch ETL workflow: ingest source files, standardise business data, integrate related records, and make the result available for analytical queries.

| Layer | Implementation | Purpose |
|---|---|---|
| Bronze | Six PostgreSQL tables and `bronze.load_bronze()` | Load source CSV data using `COPY` |
| Silver | Six PostgreSQL tables and `silver.load_silver()` | Clean, deduplicate, transform, and standardise bronze data |
| Gold | Two dimension views and one fact view | Present an integrated sales model for analysis |

**Technology:** PostgreSQL, SQL, PL/pgSQL, CSV, VS Code with SQLTools, pgAdmin, and Git/GitHub.

## Medallion Architecture

**Medallion Architecture** organises data into three layers of increasing refinement: Bronze preserves the source records, Silver cleans and standardises them, and Gold integrates them into a business-facing model. This project implements those layers as schemas inside PostgreSQL.

![Animated PostgreSQL Medallion Architecture: CRM and ERP CSV sources flow through Bronze raw tables, Silver cleaned tables, and Gold dimensional views to SQL analysis](02_docs/medallion_architecture.gif)

*The animation illustrates the flow; it is not a live execution monitor. Gold views read Silver when queried rather than loading another physical copy.*

### Follow one record through the warehouse

1. **Source:** a customer arrives in a CRM CSV, with related demographic and location details in ERP files.
2. **Bronze — ingest:** `bronze.load_bronze()` uses `COPY` to load the six CSV files into source-shaped tables.
3. **Silver — refine:** `silver.load_silver()` removes missing customer IDs, keeps the latest record per customer, trims names, and standardises codes and identifiers.
4. **Gold — integrate:** `gold.dim_customers` joins the cleaned CRM customer with ERP birthdate, gender, and country information. Product and sales views complete the dimensional model.
5. **Consume:** SQL queries join the fact and dimension views to explore sales, products, and customers.

| Design decision | Implementation |
|---|---|
| Layer separation | `bronze`, `silver`, and `gold` schemas in PostgreSQL |
| Bronze and Silver loading | Batch processing with full refreshes |
| Orchestration | Explicit calls to the two PL/pgSQL procedures |
| Gold storage | Two dimension views and one fact view; no separate Gold load |
| Load visibility | Progress notices, elapsed timings, and exception handling |
| Consumption | Analytical SQL; the model can support downstream BI tools |

### Reference architecture and design documents

<details>
<summary>View the original learning-project architecture</summary>

![Original Data with Baraa reference architecture](02_docs/data_architecture.png)

This reference diagram is from the SQL Server learning material. The animated diagram above reflects this repository's PostgreSQL implementation. BI tools and machine-learning consumers shown in the reference are possible downstream uses, not delivered components of this repository.

</details>

Explore the [data flow](02_docs/data_flow.png), [integration](02_docs/data_integration.png), and [data model](02_docs/data_model.png) diagrams for more detail.

## Source data

| System | CSV file | Destination in bronze |
|---|---|---|
| CRM | `cust_info.csv` | `bronze.crm_cust_info` |
| CRM | `prd_info.csv` | `bronze.crm_prd_info` |
| CRM | `sales_details.csv` | `bronze.crm_sales_details` |
| ERP | `CUST_AZ12.csv` | `bronze.erp_cust_az12` |
| ERP | `LOC_A101.csv` | `bronze.erp_loc_a101` |
| ERP | `PX_CAT_G1V2.csv` | `bronze.erp_px_cat_g1v2` |

The datasets are included in [01_datasets](01_datasets/). Headers are skipped during import; values are mapped by column order.

## Transformation highlights

- **Customers:** remove records with missing customer IDs, retain the latest record per customer using `ROW_NUMBER()`, trim names, and standardise gender and marital status.
- **Products:** extract category and product identifiers, replace missing costs, standardise product lines, and derive version end dates using `LEAD()`.
- **Sales:** convert integer dates to PostgreSQL dates, recalculate selected inconsistent sales amounts, and derive missing or nonpositive prices with division-by-zero protection.
- **ERP customers:** remove the `NAS` identifier prefix, reject future birthdates, and standardise gender values.
- **Locations:** normalise customer identifiers and country labels.
- **Categories:** carry category, subcategory, and maintenance attributes into silver.

Both load procedures report elapsed time and re-raise errors. Changes within a failed procedure's protected block are rolled back. Bronze and silver calls are separate transactions unless explicitly wrapped together by the caller.

## Gold model

| View | Contents |
|---|---|
| `gold.dim_customers` | Customer details enriched with ERP birthdates and country; CRM gender takes precedence when available |
| `gold.dim_products` | Current product versions enriched with category and maintenance details |
| `gold.fact_sales` | Sales rows with customer/product keys, dates, quantity, price, and sales amount |

The intended fact grain is a source sales line, not one row per order. Dimension relationships are implemented with joins; these views do not enforce foreign-key constraints.

### Example: sales by product category

```sql
SELECT
    p.category,
    SUM(f.sales_amount) AS total_sales,
    SUM(f.quantity) AS units_sold
FROM gold.fact_sales AS f
LEFT JOIN gold.dim_products AS p
    ON f.product_key = p.product_key
GROUP BY p.category
ORDER BY total_sales DESC;
```

### Example: monthly sales

```sql
SELECT
    DATE_TRUNC('month', order_date)::DATE AS sales_month,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT order_number) AS orders
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY 1
ORDER BY 1;
```

## Repository guide

| Location | Contents |
|---|---|
| [01_datasets/](01_datasets/) | CRM and ERP source CSVs |
| [02_docs/](02_docs/) | Diagrams, requirements, catalog, naming conventions, and project notes |
| [03_Scripts/init_database.sql](03_Scripts/init_database.sql) | Creates schemas in an existing database |
| [03_Scripts/Bronze/](03_Scripts/Bronze/) | Bronze table definitions and CSV load procedure |
| [03_Scripts/Silver/](03_Scripts/Silver/) | Silver table definitions and transformation procedure |
| [03_Scripts/Gold/](03_Scripts/Gold/) | Gold dimension and fact view definitions |
| [04_Setup/README.md](04_Setup/README.md) | PostgreSQL installation, connection, paths, execution order, and troubleshooting |

## Run the project

Follow the [PostgreSQL setup guide](04_Setup/README.md) for the complete first-run sequence.

1. Create and connect to `SQL_Data_Warehouse`.
2. Run the schema initialisation script.
3. Create bronze tables, update all CSV paths, and run the bronze loader script.
4. Create silver tables, define the silver procedure, and call it.
5. Run the gold view script and query the results.

> The bronze loader script already ends with `CALL bronze.load_bronze();`. The silver loader script defines its procedure but requires a separate `CALL silver.load_silver();`.

For later data refreshes, after setup:

```sql
CALL bronze.load_bronze();
CALL silver.load_silver();
```

Gold views reflect the updated silver data automatically. Table-creation scripts drop existing tables; they are not needed for routine refreshes.

## Scope and implementation notes

- This is a local batch warehouse project using full refreshes; no scheduler or incremental ingestion is included.
- Gold uses regular views, not persisted fact/dimension tables or materialized views.
- Dimension keys are generated with `ROW_NUMBER()` and can change when the underlying data changes. They are not durable identifiers for external systems.
- Sales date conversion assumes that positive eight-digit date values represent valid calendar dates.
- Customer records tied on the latest creation date have no additional tie-breaker in the current deduplication query.
- Source joins assume compatible identifiers and cardinalities. The repository does not establish a production data-quality guarantee.
- Some supporting reference documents retain SQL Server terminology and types such as `NVARCHAR`. The executable scripts and this setup guide describe the PostgreSQL implementation.

## Learning context

Developed while following Data with Baraa's SQL data warehouse learning project, with the implementation adapted to PostgreSQL. The work covers CSV ingestion, stored procedures, window functions, transformations, dimensional modelling, and version control.
