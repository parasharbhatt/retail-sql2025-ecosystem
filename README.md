

# SQL Server 2025 Retail OLTP & Data Warehouse Ecosystem

A SQL Server 2025 reference implementation of a retail **OLTP (`Retail_OLTP`)** database and a **Kimball star-schema data warehouse (`Retail_DW`)**. 

The project includes timestamp-aware SCD Type 2 processing, incremental fact loading, SQL Server Agent scheduling, and a reporting view.

## Project Category

`Data Engineering` `Data Warehouse` `Retail Analytics` `OLTP` `Business Intelligence` `ETL`

## Tools Used

`SQL Server 2025` `T-SQL` `SQL Server Agent` `Power BI` `VS Code` `MSSQL Extension` `SQL Server MCP`



---

## Architecture Overview

* **Source Layer (`Retail_OLTP`):** Transactional tables (`Customers`, `Products`, `SalesHeader`, `SalesDetail`) seeded with 100 customers, 100 products, and approximately three years of simulated orders. `SalesHeader.OrderDateTimeUtc` stores the UTC event time. `OrderDate` is a persisted computed date projection. Update triggers maintain UTC `LastModified` timestamps for incremental processing.
* **Warehouse Layer (`Retail_DW`):**
  * **SCD Type 2 Dimensions:** `DimCustomers` and `DimProducts` track history with `ValidFrom`, `ValidTo`, and `IsCurrent`. Initial versions start at `1900-01-01` to cover historical orders. For a changed row, the ETL closes the old version and captures its resulting `ValidTo` from `MERGE OUTPUT` as the new version's `ValidFrom`.
  * **Temporal Fact Table:** `FactSales` stores `OrderDateTimeUtc`; `OrderDate` is computed from it. The ETL resolves `CustomerKey` and `ProductKey` using half-open intervals: `ValidFrom <= OrderDateTimeUtc < ValidTo`. Each staged sale must match exactly one version of each dimension or the ETL fails.
  * **Incremental Ingestion:** `DW_Watermarks` is initialized to `1900-01-01` for `DimCustomers`, `DimProducts`, and `FactSales`. Later runs use source `LastModified` values to detect changes; changed fact rows are deleted and reinserted to prevent duplicates.
  * **Error Logging:** On failure, the ETL rolls back its data transaction, writes the error to `ETL_Error_Log`, and rethrows it.
* **Automation & BI Layer:**
  * **SQL Server Agent Job:** `DW_Nightly_Orchestration_Pipeline` runs `sp_Execute_Warehouse_Nightly_ETL` daily at **2:00 AM server-local time**.
  * **Presentation View:** `dbo.vPresentation_SalesFact` joins facts to customer and product attributes for reporting.
  * **Power BI Project:** An Import-mode PBIP semantic model and three-page retail analytics report are in [`powerbi/`](./powerbi/). The report uses a professional teal/blue theme with 14 pt visual titles and 12 pt legends and axis labels; see the [Power BI guide](./powerbi/README.md).

> **Warning:** Part 1 drops and recreates `Retail_OLTP`; Part 2 drops and recreates `Retail_DW`. Re-running either script deletes all data in that database. Use them only when intentionally rebuilding the environment.

---

## Repository Structure

```text
retail-sql2025-ecosystem/
├── .github/
│   └── copilot-instructions.md                  # SQL conventions and project requirements
├── sql/
│   ├── part1_oltp/
│   │   └── 01_retail_oltp_setup.sql             # Retail_OLTP DB, tables & 3-year seed
│   ├── part2_dw_core/
│   │   └── 01_retail_dw_schema.sql              # Retail_DW DB, logs, watermarks, SCD2 & FactSales
│   ├── part3_etl_pipeline/
│   │   └── 01_sp_Execute_Warehouse_Nightly_ETL.sql  # Incremental SCD2 & temporal Fact ETL
│   └── part4_agent_and_bi/
│       └── 01_agent_job_and_bi_view.sql         # 2:00 AM SQL Agent job & vPresentation_SalesFact
├── powerbi/
│   ├── README.md                                # Power BI setup, refresh, and report guide
│   ├── RetailSalesAnalytics.pbip
│   ├── RetailSalesAnalytics.Report/
│   │   ├── definition/
│   │   └── StaticResources/RegisteredResources/
│   │       └── RetailProfessionalTheme.json
│   └── RetailSalesAnalytics.SemanticModel/
├── .gitignore
└── README.md
```

---

## Prerequisites

1. A SQL Server 2025 instance with permission to create/drop databases and objects. Part 1 and Part 2 require database-level privileges.
2. SQL Server Agent enabled and running on an edition that supports it; required for Part 4.
3. Visual Studio Code with the SQL Server (`mssql`) extension, or the SQL Server MCP extension, connected to the same SQL Server instance. The built-in extension connection does not require a repository `.vscode/mcp.json`.
4. Permission to create and manage SQL Server Agent jobs in `msdb` if deploying Part 4.
5. Power BI Desktop to open and refresh the PBIP report; report credentials are configured locally and are not stored in the repository.

---

## Setup & Execution Steps

### 1. Connect to SQL Server
1. Connect to the SQL Server instance using the VS Code SQL Server extension or SQL Server MCP extension.
2. The scripts use `GO` batch separators and contain their own `USE` statements. Execute each complete script in the order below.

### 2. Deploy the Four SQL Layers Sequentially

| Step | Script Path | Description |
| :--- | :--- | :--- |
| **Part 1** | `sql/part1_oltp/01_retail_oltp_setup.sql` | Drops/recreates `Retail_OLTP`, creates the source tables and timestamp triggers, and seeds customers, products, and orders. |
| **Part 2** | `sql/part2_dw_core/01_retail_dw_schema.sql` | Drops/recreates `Retail_DW`, creates the error log, watermarks, dimensions, fact table, and lookup indexes. |
| **Part 3** | `sql/part3_etl_pipeline/01_sp_Execute_Warehouse_Nightly_ETL.sql` | Creates or alters the incremental SCD Type 2 and point-in-time fact ETL procedure. |
| **Part 4** | `sql/part4_agent_and_bi/01_agent_job_and_bi_view.sql` | Recreates the daily SQL Server Agent job and creates or alters `dbo.vPresentation_SalesFact`. |

### 3. Run the Initial Load and Verify

Run the ETL procedure once after deploying Parts 1–3. The seeded `1900-01-01` watermarks cause the initial run to process the historical source data. Subsequent executions are incremental.

```sql
USE Retail_DW;
GO

EXEC dbo.sp_Execute_Warehouse_Nightly_ETL;

SELECT TableName, LastRunDateTime
FROM dbo.DW_Watermarks
ORDER BY TableName;

SELECT COUNT_BIG(*) AS FactSalesRows
FROM dbo.FactSales;

SELECT TOP (20)
    OrderDateTimeUtc, OrderDate, CustomerName, ProductName, SalesAmount
FROM dbo.vPresentation_SalesFact
ORDER BY OrderDateTimeUtc DESC;

SELECT TOP (20) *
FROM dbo.ETL_Error_Log
ORDER BY LogDateTime DESC;
```

`OrderDate` is derived from `OrderDateTimeUtc`; use the timestamp for time-accurate SCD version resolution. The Agent schedule is based on the SQL Server host's local time, not UTC.

## Open the Power BI report

After deploying the SQL layers and running the initial ETL, open [`powerbi/RetailSalesAnalytics.pbip`](./powerbi/RetailSalesAnalytics.pbip) in Power BI Desktop. Configure the local SQL Server data-source credentials and refresh the Import-mode model as needed. For model parameters, report pages, and theme details, see [`powerbi/README.md`](./powerbi/README.md).

## Re-running Scripts

* **Parts 1 and 2:** destructive rebuilds; do not rerun unless you intend to erase and recreate the corresponding database.
* **Part 3:** uses `CREATE OR ALTER PROCEDURE`; it updates the ETL procedure definition without rebuilding the warehouse.
* **Part 4:** deletes and recreates the named SQL Server Agent job, then creates or alters the presentation view.
* **ETL procedure:** safe for repeated incremental execution under the configured watermarks; review `ETL_Error_Log` if an execution fails.
