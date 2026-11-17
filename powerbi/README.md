# Power BI Retail Analytics

This folder contains the Import-mode Power BI project: the `RetailSalesAnalytics` semantic model and its three-page report. For the SQL Server, warehouse, and ETL setup, see the [repository README](../README.md).

## Open, connect, and refresh

1. Deploy the SQL layers and run the initial warehouse ETL load as described in the [repository setup guide](../README.md).
2. Open [RetailSalesAnalytics.pbip](./RetailSalesAnalytics.pbip) in Power BI Desktop.
3. The semantic model parameters `Server` and `Database` are defined in `RetailSalesAnalytics.SemanticModel/definition/expressions.tmdl`. Update them if your SQL Server instance or warehouse database differs from the defaults.
4. Configure SQL Server credentials in Power BI Desktop's data source settings, then refresh the model. Credentials are local and are not stored in this repository.

The model imports `DimCustomers`, `DimProducts`, and `FactSales`. `DimDate` is generated during model refresh from the minimum and maximum fact order dates. `FactSales.OrderDateTimeUtc` is available for timestamp-level analysis and is hidden from the report field list by default.

## Model and report contents

- `all_measures` contains Basic Measures and Advanced Measures display folders.
- `Time Intelligence` is a calculation group with Current, MTD, QTD, YTD, Previous Year, YoY Change, and YoY % items.
- The report pages are Executive Overview, Product & Customer Analysis, and Time Intelligence.

## Report design

The report uses the registered **Retail Professional** theme in [RetailProfessionalTheme.json](./RetailSalesAnalytics.Report/StaticResources/RegisteredResources/RetailProfessionalTheme.json). Its light canvas, white visual cards, subtle borders, and teal/blue palette with warm accent colors are designed for clear contrast.

- Visual titles: 14 pt, semibold.
- Legends and chart-axis labels: 12 pt.
- Card values: 32 pt; supporting labels: 12 pt.

The theme is registered in `RetailSalesAnalytics.Report/definition/report.json`. If you rename or move the theme file, update its `themeCollection.customTheme` entry and `resourcePackages` registration as well.
