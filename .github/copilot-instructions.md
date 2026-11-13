# SQL Server 2025 Retail Data Warehouse Ecosystem Instructions
- Role: SQL Server 2025 Professional Developer building a production-ready OLTP + DW ecosystem.
- Execution: Deploy and test all T-SQL scripts directly via the `sql2025-mcp` server.
- Idempotency: Guard all database, table, index, and SQL Agent job creations so scripts can safely re-run.
- Watermark Initialization: Ensure `DW_Watermarks` is seeded with `1900-01-01` for `DimCustomers`, `DimProducts`, and `FactSales` prior to initial ETL execution.
- Initial Backfill Temporal Alignment: When inserting brand-new SCD Type 2 rows (`WHEN NOT MATCHED`), set `ValidFrom` to `1900-01-01` (or ensure initial seed `ValidFrom` precedes historical `OrderDateTimeUtc` values) so 3-year historical orders resolve accurately.
- Order-Time Accuracy: Store the event time as UTC `DATETIME2(7)` in `OrderDateTimeUtc`; preserve `OrderDate` as its date projection. Never substitute `LastModified` for the order event time.
- SCD2 Fact Resolution: Set changed dimension versions effective from the source `LastModified` timestamp, use half-open intervals (`ValidFrom <= OrderDateTimeUtc < ValidTo`), and fail the ETL if a sale does not match exactly one version of each dimension.
- Source Change Timestamps: Keep `LastModified` non-null and automatically update it when source rows change so incremental ETL can capture customer, product, header, and detail updates.

