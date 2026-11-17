# Copilot Instructions: Retail SQL Server 2025 Ecosystem

## Role and execution

- **Role:** Act as a SQL Server 2025 professional developer building a production-ready OLTP and data warehouse ecosystem.
- **SQL execution:** Deploy and test T-SQL scripts through the `sql2025-mcp` server.

## SQL Server and ETL standards

- **Idempotency:** Guard database, table, index, and SQL Server Agent job creation so scripts can be rerun safely.
- **Watermark initialization:** Seed `DW_Watermarks` with `1900-01-01` for `DimCustomers`, `DimProducts`, and `FactSales` before the initial ETL execution.
- **Initial backfill alignment:** When inserting new SCD Type 2 rows (`WHEN NOT MATCHED`), set `ValidFrom` to `1900-01-01`, or ensure the initial value precedes historical `OrderDateTimeUtc` values, so historical orders resolve accurately.
- **Order-time accuracy:** Store the event time in `OrderDateTimeUtc` as UTC `DATETIME2(7)`. Preserve `OrderDate` as its date projection; never use `LastModified` as the order event time.
- **SCD Type 2 fact resolution:** Make changed dimension versions effective at the source `LastModified` timestamp. Use half-open intervals (`ValidFrom <= OrderDateTimeUtc < ValidTo`) and fail ETL if a sale does not match exactly one version of each dimension.
- **Source change timestamps:** Keep `LastModified` non-null and update it automatically when source rows change, so incremental ETL captures customer, product, header, and detail updates.

## Power BI project

### Project and model

- **Project location:** The PBIP project is `powerbi/RetailSalesAnalytics.pbip`. Preserve the report and semantic model references.
- **Report pages:** Preserve Executive Overview, Product & Customer Analysis, and Time Intelligence, including existing visual queries and semantic-model bindings.
- **Semantic model:** The Import-mode model reads `DimCustomers`, `DimProducts`, and `FactSales` from `Retail_DW`; `DimDate` is generated during model refresh. Preserve `FactSales.OrderDateTimeUtc` as the UTC event timestamp, and keep credentials out of the repository.
- **Time intelligence:** Preserve the `Time Intelligence` calculation group and its existing calculation items when changing measures or visuals.

### PBIR format and theme

- **PBIR format:** Keep the report in PBIR format under `RetailSalesAnalytics.Report/definition/`. Preserve schema markers, page and visual identifiers, and the `.pbip` model reference. Do not replace the PBIR definition with a root-level legacy `report.json` or downgrade its schema metadata.
- **Theme registration:** The report uses `RetailSalesAnalytics.Report/StaticResources/RegisteredResources/RetailProfessionalTheme.json`. If the theme is moved or renamed, update both `themeCollection.customTheme` and its `resourcePackages` entry in `definition/report.json`.
- **Visual design:** Follow the Retail Professional theme: light canvas, white visual cards, teal/blue primary colors with warm accents, 14 pt semibold visual titles, 12 pt legends and axis labels, and 32 pt KPI card values with 12 pt supporting labels. Maintain clear contrast and consistent formatting across all pages.

### Validation

- **Report or theme changes:** Validate affected JSON and confirm the registered theme path matches the file. Open the PBIP in Power BI Desktop when available to check rendering. Do not refresh the semantic model unless the task requires it.

