# Retail sales Power BI project

Open [RetailSalesAnalytics.pbip](./RetailSalesAnalytics.pbip) in Power BI Desktop. The report uses an Import-mode semantic model over `Retail_DW` on `PB_DELL_M18`.

## Data source and refresh

The semantic model parameters `Server` and `Database` are in `RetailSalesAnalytics.SemanticModel/definition/expressions.tmdl`. Change them if the SQL Server instance or warehouse database differs, then apply the changes and refresh the model in Power BI Desktop. The project does not include credentials; configure SQL Server authentication through Power BI's data source settings.

The model imports `DimCustomers`, `DimProducts`, and `FactSales`. `DimDate` is generated during model refresh from the minimum and maximum fact order dates. `FactSales.OrderDateTimeUtc` remains available for timestamp-level analysis and is hidden from the report field list by default.

## Model and report

- `all_measures` contains Basic Measures and Advanced Measures display folders.
- `Time Intelligence` is a calculation group with Current, MTD, QTD, YTD, Previous Year, YoY Change, and YoY % items.
- The report includes Executive Overview, Product & Customer Analysis, and Time Intelligence pages.

The first refresh requires connectivity and read access to the three warehouse tables. The SQL MCP connection was unavailable when this project was created, so no local model cache or imported data is included.
