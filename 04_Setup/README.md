# PostgreSQL setup guide

[Back to project overview](../README.md)

This guide runs the repository on a local Windows PostgreSQL installation using VS Code and SQLTools. pgAdmin's Query Tool can run the same SQL. The examples use **PostgreSQL 18** and the database name **SQL_Data_Warehouse**.

## 1. Prepare the tools and project folder

Install PostgreSQL with its command-line tools and optionally pgAdmin. In VS Code, install SQLTools and its PostgreSQL/Cockroach driver. Install Git if you want to clone and track the project.

For a new checkout, open a Windows terminal and run:

```bat
cd /d D:\
git clone https://github.com/klt-ramkumar/Advance_SQL_Data_Warehouse_Project.git SQL_Data_warehouse
cd SQL_Data_warehouse
code .
```

If `D:\SQL_Data_warehouse` already contains your project, open that existing folder instead of cloning over it.

The repository contains six CSVs under `01_datasets`, documentation under `02_docs`, and executable SQL under `03_Scripts`.

## 2. Create the database

Connect to the existing `postgres` maintenance database using pgAdmin or SQLTools. Execute the following statement by itself, outside an explicit transaction:

```sql
CREATE DATABASE "SQL_Data_Warehouse";
```

Skip this step if the database already exists. Double quotes preserve the mixed-case database name.

Next, reconnect to **SQL_Data_Warehouse**. PostgreSQL does not support SQL Server's `USE database_name`; select the database in the connection settings.

For SQLTools, use your local installation's details:

| Setting | Example |
|---|---|
| Connection name | `local_postgres` |
| Server / host | `localhost` |
| Port | `5432` (unless configured differently) |
| Database | `SQL_Data_Warehouse` |
| Username | Your PostgreSQL login, often `postgres` for local learning |
| Password | The password set for that PostgreSQL login |

Do not commit connection passwords. The repository's `.gitignore` excludes `.vscode/` and `.env`.

Confirm the target:

```sql
SELECT current_database(), current_user;
```

## 3. Initialise the schemas

Run [03_Scripts/init_database.sql](../03_Scripts/init_database.sql).

Despite its filename, this script creates **schemas**, not the database itself:

- `bronze`
- `silver`
- `gold`

In VS Code, run SQL using the **SQLTools** commands associated with your PostgreSQL connection. Select complete procedure definitions, including their dollar-quoted bodies, when executing them.

## 4. Check the CSV paths before loading

Open [03_Scripts/Bronze/load_csv.sql](../03_Scripts/Bronze/load_csv.sql).

Its absolute paths currently start with:

```text
D:/SQL_Data_warehouse/01_datasets/
```

If you cloned to another folder, change all six paths before executing the script.

Use these exact filenames from the repository:

| Table | File relative to 01_datasets |
|---|---|
| `bronze.crm_cust_info` | `source_crm/cust_info.csv` |
| `bronze.crm_prd_info` | `source_crm/prd_info.csv` |
| `bronze.crm_sales_details` | `source_crm/sales_details.csv` |
| `bronze.erp_cust_az12` | `source_erp/CUST_AZ12.csv` |
| `bronze.erp_loc_a101` | `source_erp/LOC_A101.csv` |
| `bronze.erp_px_cat_g1v2` | `source_erp/PX_CAT_G1V2.csv` |

**Filename casing:** the loader currently spells ERP filenames in lowercase. This normally works on Windows, but on a case-sensitive filesystem you must update them to match the uppercase names above.

### How COPY accesses files

`COPY ... FROM 'path'` reads from the **database server's filesystem**, not from the VS Code editor.

For this local workflow:

- The PostgreSQL service account needs operating-system read access to the CSV files and access through their parent directories.
- The database login needs the relevant table permissions and permission for server-side file reads (a superuser or an appropriately authorised role, such as one granted `pg_read_server_files`).
- Prefer narrowly managed access; do not make broad role grants merely to avoid diagnosing a file-path problem.

A remote, containerised, or managed PostgreSQL instance cannot automatically read your laptop's D: drive. That requires a different ingestion arrangement, such as client-side loading or files made available to the database server. The procedure here uses server-side COPY.

## 5. Execute the first-run sequence

Use a dedicated project database: table-creation scripts drop and recreate tables, and loader calls replace their contents.

Run the following in order. Stop if a step errors.

| Step | Script or SQL | Effect |
|---|---|---|
| 1 | `03_Scripts/init_database.sql` | Create schemas |
| 2 | `03_Scripts/Bronze/Table_creation.sql` | Create six bronze tables |
| 3 | `03_Scripts/Bronze/load_csv.sql` | Define the bronze procedure **and immediately call it** |
| 4 | `03_Scripts/Silver/Table_creation_silver.sql` | Create six silver tables |
| 5 | `03_Scripts/Silver/load_files.sql` | Define the silver procedure |
| 6 | `CALL silver.load_silver();` | Transform bronze into silver |
| 7 | `03_Scripts/Gold/load_data.sql` | Create three gold views |

The bronze file already includes a call at its end. Do not add another call unless you intend another full reload.

The silver definition does not execute itself. After running its file, run:

```sql
CALL silver.load_silver();
```

There is no `gold.load_gold()` procedure. Execute the gold SQL file directly.

## 6. View the result

These queries are simple previews of the finished model, not a test suite:

```sql
SELECT * FROM gold.dim_customers LIMIT 10;
SELECT * FROM gold.dim_products LIMIT 10;
SELECT * FROM gold.fact_sales LIMIT 10;
```

To see the views listed in PostgreSQL:

```sql
SELECT table_schema, table_name
FROM information_schema.views
WHERE table_schema = 'gold'
ORDER BY table_name;
```

Expected names: `dim_customers`, `dim_products`, and `fact_sales`.

A successful `CALL` does not return a results table. The procedures send `RAISE NOTICE` messages; their visibility depends on the client. In pgAdmin, look in the Messages tab. In SQLTools, query the data even if notices are not visible.

## 7. Refresh after changing source CSVs

After the first setup, run:

```sql
CALL bronze.load_bronze();
CALL silver.load_silver();
```

Execute the silver call only after the bronze call succeeds. Regular gold views read the updated silver tables, so no materialized-view refresh is required.

Do not rerun table-creation scripts for routine refreshes. In particular, dropping silver tables after gold views exist can fail because the views depend on those tables.

If you edit a procedure's SQL file, execute its complete `CREATE OR REPLACE PROCEDURE` statement to update the database definition. Saving a file in VS Code alone does not change the stored procedure. Running the complete bronze loader file also triggers its final `CALL`.

### Transaction behaviour

Each procedure has a protected block with exception handling. If a load fails, changes within that block are undone and the error is re-raised. Separate successful bronze and silver calls are not automatically one combined transaction.

With auto-commit enabled, a successful standalone call commits. If you explicitly started a transaction and it fails, run `ROLLBACK;` in that same connection before retrying.

## 8. Troubleshooting

| Symptom | What to check |
|---|---|
| `relation does not exist` | Confirm the database and run schema/table creation in order |
| `procedure does not exist` | Execute its complete definition in the same database before calling it |
| `could not open file` | Confirm the absolute server-side path, filename case, and file existence |
| `permission denied` during COPY | Check both the PostgreSQL service account's file access and database-role privileges |
| Invalid integer/date or missing/extra CSV columns | Check the reported row, column order, delimiter, and target data types |
| Invalid date during silver load | The script assumes positive eight-digit dates are valid calendar dates; inspect the reported source value |
| No table output from CALL | Expected: use SELECT to view data; notices are separate messages |
| `current transaction is aborted` | Run `ROLLBACK;` in the same session, fix the original error, then retry |
| Cannot drop silver tables because other objects depend on them | Use the refresh procedures; schema rebuilds require planned handling of dependent gold views |
| Prompt to create another connection profile | Ensure the command belongs to SQLTools and select the existing PostgreSQL connection |

## 9. Save changes to GitHub

The SQL files are the version-controlled project source. Tables, rows, and procedure definitions inside PostgreSQL are separate from Git.

From the project folder, after saving your files:

```bash
git status
git add .
git diff --cached --stat
git commit -m "Update PostgreSQL warehouse"
git push
```

Review staged files before committing. If documentation has been updated directly on GitHub, save and commit your local work, then use `git pull --no-rebase origin main` to bring those changes into your folder before the next push. Resolve any reported conflicts before continuing.

## PostgreSQL adaptation reference

| SQL Server pattern | PostgreSQL used here |
|---|---|
| `CREATE OR ALTER PROCEDURE` | `CREATE OR REPLACE PROCEDURE ... LANGUAGE plpgsql` |
| `EXEC procedure_name` | `CALL procedure_name()` |
| `BULK INSERT` | `COPY ... WITH (FORMAT CSV, HEADER TRUE)` |
| `NVARCHAR` | `VARCHAR` with a suitable database encoding, such as UTF-8 |
| `DATETIME` | `TIMESTAMP` |
| Warehouse load timestamp | `TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP` |
| `PRINT` | `RAISE NOTICE` inside PL/pgSQL |
| `GETDATE()` for elapsed timing | `clock_timestamp()` |
| `TRY / CATCH` | `BEGIN ... EXCEPTION ... END` |
| `USE database_name` | Reconnect to the target database |
| `GO` | Omit; end statements with semicolons |

Some documents under `02_docs` retain terminology from the SQL Server learning material. Follow the PostgreSQL scripts and this guide for execution.
