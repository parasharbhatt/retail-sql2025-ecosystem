

# SQL Server 2025 Retail OLTP & Data Warehouse Ecosystem

A production-ready, version-controlled **OLTP (`Retail_OLTP`)** and **Kimball Star Schema Data Warehouse (`Retail_DW`)** ecosystem built in **SQL Server 2025** using **VS Code**, **Git**, **GitHub Copilot Custom Instructions**, and the **SQL MCP Server**.

---

## Architecture Overview

* **Source Layer (`Retail_OLTP`):** Normalized transactional schema (`Customers`, `Products`, `SalesHeader`, `SalesDetail`) seeded with 100 baseline customers, 100 products, and 3 years of simulated retail orders. `SalesHeader.OrderDateTimeUtc` stores the UTC event time; `OrderDate` remains available as its date-only projection.
* **Warehouse Layer (`Retail_DW`):**
  * **SCD Type 2 Dimensions:** `DimCustomers` and `DimProducts` track historical attribute changes via `ValidFrom`, `ValidTo`, and `IsCurrent`; changed versions become effective at the source row's UTC `LastModified` time.
  * **Temporal Fact Table:** `FactSales` retains `OrderDateTimeUtc` and resolves surrogate keys (`CustomerKey`, `ProductKey`) against half-open dimension intervals (`ValidFrom <= OrderDateTimeUtc < ValidTo`).
  * **Incremental Ingestion:** `DW_Watermarks` tracks `LastRunDateTime` per table to process only modified OLTP records.
  * **Centralized Error Logging:** `ETL_Error_Log` captures procedure failures inside an atomic `TRY...CATCH` transaction block.
* **Automation & BI Layer:**
  * **SQL Server Agent Job:** `DW_Nightly_Orchestration_Pipeline` runs `sp_Execute_Warehouse_Nightly_ETL` daily at **2:00 AM**.
  * **Power BI Presentation View:** `vPresentation_SalesFact` exposes a clean, denormalized semantic view for reporting.

> **Warning:** Part 1 drops and recreates `Retail_OLTP`; Part 2 drops and recreates `Retail_DW`. Running them again deletes the existing database contents.

---

## Repository Structure

```text
retail-sql2025-ecosystem/
├── .github/
│   └── copilot-instructions.md                  # Copilot architectural & T-SQL rules
├── sql/
│   ├── part1_oltp/
│   │   └── 01_retail_oltp_setup.sql             # Retail_OLTP DB, tables & 3-year seed
│   ├── part2_dw_core/
│   │   └── 01_retail_dw_schema.sql              # Retail_DW DB, logs, watermarks, SCD2 & FactSales
│   ├── part3_etl_pipeline/
│   │   └── 01_sp_Execute_Warehouse_Nightly_ETL.sql  # Incremental SCD2 & temporal Fact ETL
│   └── part4_agent_and_bi/
│       └── 01_agent_job_and_bi_view.sql         # 2:00 AM SQL Agent job & vPresentation_SalesFact
├── .gitignore
└── README.md
```

---

## Prerequisites

1. **SQL Server 2025** installed locally with **SQL Server Agent** service enabled and running.
2. **Visual Studio Code** with the **GitHub Copilot** and **SQL Server (mssql)** extensions.
3. Use the VS Code SQL Server (mssql) extension or a configured SQL MCP server to connect to the SQL Server instance. Source-table update triggers keep `LastModified` current for incremental loads. The built-in extension does not require a repository `.vscode/mcp.json`.
4. **Git** initialized in your local workspace.

---

## Setup & Execution Steps

### 1. Connect to SQL Server
1. Connect to the SQL Server instance through the VS Code SQL Server extension or your configured SQL MCP server.
2. Confirm `.github/copilot-instructions.md` is loaded via **Chat: Open Customizations**.

### 2. Deploy the Four SQL Layers Sequentially
Switch GitHub Copilot Chat to **Agent Mode** and execute each script in order via `sql2025-mcp`:

| Step | Script Path | Description |
| :--- | :--- | :--- |
| **Part 1** | `sql/part1_oltp/01_retail_oltp_setup.sql` | Creates `Retail_OLTP`, builds 4 normalized tables, and seeds 3 years of orders. |
| **Part 2** | `sql/part2_dw_core/01_retail_dw_schema.sql` | Creates `Retail_DW`, `ETL_Error_Log`, `DW_Watermarks`, SCD2 dimensions, `FactSales`, and lookup indexes. |
| **Part 3** | `sql/part3_etl_pipeline/01_sp_Execute_Warehouse_Nightly_ETL.sql` | Creates `sp_Execute_Warehouse_Nightly_ETL` for incremental SCD2 + point-in-time fact loads. |
| **Part 4** | `sql/part4_agent_and_bi/01_agent_job_and_bi_view.sql` | Schedules `DW_Nightly_Orchestration_Pipeline` (2:00 AM daily) and creates `vPresentation_SalesFact`. |

### 3. Run Initial Load & Verify
Execute the ETL pipeline manually and inspect both the UTC timestamp and date-only compatibility column:

```sql
EXEC Retail_DW.dbo.sp_Execute_Warehouse_Nightly_ETL;

SELECT TOP 20 OrderDateTimeUtc, OrderDate, CustomerName, ProductName, SalesAmount
FROM Retail_DW.dbo.vPresentation_SalesFact;
SELECT * FROM Retail_DW.dbo.DW_Watermarks;
SELECT * FROM Retail_DW.dbo.ETL_Error_Log;
```

---

## Git Workflow

Commit each layer after deploying and verifying it against your local SQL Server instance:

```bash
git add README.md
git commit -m "docs: add project README with setup and deployment guide"
```
