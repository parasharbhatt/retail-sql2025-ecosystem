-- ============================================================================
-- PART 3: TASK-2 (v) COMPLETE ETL ORCHESTRATION PIPELINE
-- ============================================================================
USE Retail_DW;
GO

CREATE OR ALTER PROCEDURE sp_Execute_Warehouse_Nightly_ETL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ExecutionTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @InitialValidFrom DATETIME2 = '1900-01-01 00:00:00.0000000';
    DECLARE @MaxExpiry DATETIME2 = '9999-12-31 23:59:59.9999999';

    BEGIN TRY
        DECLARE @CustomerChanges TABLE (
            MergeAction NVARCHAR(10),
            BusinessKey INT,
            CustomerName NVARCHAR(100),
            City NVARCHAR(50),
            Region NVARCHAR(50)
        );

        DECLARE @ProductChanges TABLE (
            MergeAction NVARCHAR(10),
            BusinessKey INT,
            ProductName NVARCHAR(100),
            Category NVARCHAR(50),
            ListPrice DECIMAL(18,2)
        );

        BEGIN TRANSACTION;

        ---------------------------------------------------------------------------------
        -- 1. PROCESSING SCD TYPE 2 DIMCUSTOMER
        ---------------------------------------------------------------------------------
        MERGE dbo.DimCustomers AS Target
        USING (
            SELECT CustomerID, CustomerName, City, Region, LastModified
            FROM Retail_OLTP.dbo.Customers
            WHERE LastModified > (SELECT LastRunDateTime FROM dbo.DW_Watermarks WHERE TableName = 'DimCustomers')
        ) AS Source
        ON (Target.CustomerID = Source.CustomerID AND Target.IsCurrent = 1)
        WHEN MATCHED AND (
            Target.CustomerName <> Source.CustomerName
            OR Target.City <> Source.City
            OR Target.Region <> Source.Region
        ) THEN
            UPDATE SET Target.ValidTo = DATEADD(MICROSECOND, -1, @ExecutionTime), Target.IsCurrent = 0
        WHEN NOT MATCHED THEN
            INSERT (CustomerID, CustomerName, City, Region, ValidFrom, ValidTo, IsCurrent)
            VALUES (Source.CustomerID, Source.CustomerName, Source.City, Source.Region, @InitialValidFrom, @MaxExpiry, 1)
        OUTPUT $action, Source.CustomerID, Source.CustomerName, Source.City, Source.Region
            INTO @CustomerChanges (MergeAction, BusinessKey, CustomerName, City, Region);

        INSERT INTO dbo.DimCustomers (CustomerID, CustomerName, City, Region, ValidFrom, ValidTo, IsCurrent)
        SELECT BusinessKey, CustomerName, City, Region, @ExecutionTime, @MaxExpiry, 1
        FROM @CustomerChanges
        WHERE MergeAction = 'UPDATE';

        UPDATE dbo.DW_Watermarks SET LastRunDateTime = @ExecutionTime WHERE TableName = 'DimCustomers';

        ---------------------------------------------------------------------------------
        -- 2. PROCESSING SCD TYPE 2 DIMPRODUCT
        ---------------------------------------------------------------------------------
        MERGE dbo.DimProducts AS Target
        USING (
            SELECT ProductID, ProductName, Category, ListPrice, LastModified
            FROM Retail_OLTP.dbo.Products
            WHERE LastModified > (SELECT LastRunDateTime FROM dbo.DW_Watermarks WHERE TableName = 'DimProducts')
        ) AS Source
        ON (Target.ProductID = Source.ProductID AND Target.IsCurrent = 1)
        WHEN MATCHED AND (
            Target.ProductName <> Source.ProductName
            OR Target.Category <> Source.Category
            OR Target.ListPrice <> Source.ListPrice
        ) THEN
            UPDATE SET Target.ValidTo = DATEADD(MICROSECOND, -1, @ExecutionTime), Target.IsCurrent = 0
        WHEN NOT MATCHED THEN
            INSERT (ProductID, ProductName, Category, ListPrice, ValidFrom, ValidTo, IsCurrent)
            VALUES (Source.ProductID, Source.ProductName, Source.Category, Source.ListPrice, @InitialValidFrom, @MaxExpiry, 1)
        OUTPUT $action, Source.ProductID, Source.ProductName, Source.Category, Source.ListPrice
            INTO @ProductChanges (MergeAction, BusinessKey, ProductName, Category, ListPrice);

        INSERT INTO dbo.DimProducts (ProductID, ProductName, Category, ListPrice, ValidFrom, ValidTo, IsCurrent)
        SELECT BusinessKey, ProductName, Category, ListPrice, @ExecutionTime, @MaxExpiry, 1
        FROM @ProductChanges
        WHERE MergeAction = 'UPDATE';

        UPDATE dbo.DW_Watermarks SET LastRunDateTime = @ExecutionTime WHERE TableName = 'DimProducts';

        ---------------------------------------------------------------------------------
        -- 3. INCREMENTAL FACT PROCESSING WITH POINT-IN-TIME SURROGATE KEY JOIN PATTERN
        ---------------------------------------------------------------------------------
        SELECT
            d.OrderDetailID, h.OrderID, h.OrderDate, h.CustomerID, d.ProductID, d.Quantity, d.UnitPrice,
            CASE WHEN h.LastModified > d.LastModified THEN h.LastModified ELSE d.LastModified END AS CombinedLastModified
        INTO #DeltaStage
        FROM Retail_OLTP.dbo.SalesDetail d
        JOIN Retail_OLTP.dbo.SalesHeader h ON d.OrderID = h.OrderID
        WHERE h.LastModified > (SELECT LastRunDateTime FROM DW_Watermarks WHERE TableName = 'FactSales')
           OR d.LastModified > (SELECT LastRunDateTime FROM DW_Watermarks WHERE TableName = 'FactSales');

        -- Clear down existing fact entries to ensure idempotency (no duplicates)
        DELETE FROM dbo.FactSales WHERE OrderDetailID IN (SELECT OrderDetailID FROM #DeltaStage);

        -- Insert transactions mapped to the dimension version active on OrderDate
        INSERT INTO dbo.FactSales (OrderDetailID, OrderID, OrderDate, CustomerKey, ProductKey, Quantity, UnitPrice, SalesAmount)
        SELECT
            stg.OrderDetailID,
            stg.OrderID,
            stg.OrderDate,
            COALESCE(dc.CustomerKey, 1),
            COALESCE(dp.ProductKey, 1),
            stg.Quantity,
            stg.UnitPrice,
            (stg.Quantity * stg.UnitPrice)
        FROM #DeltaStage stg
        LEFT JOIN dbo.DimCustomers dc
            ON stg.CustomerID = dc.CustomerID
           AND CAST(stg.OrderDate AS DATETIME2) BETWEEN dc.ValidFrom AND dc.ValidTo
        LEFT JOIN dbo.DimProducts dp
            ON stg.ProductID = dp.ProductID
           AND CAST(stg.OrderDate AS DATETIME2) BETWEEN dp.ValidFrom AND dp.ValidTo;

        UPDATE dbo.DW_Watermarks SET LastRunDateTime = @ExecutionTime WHERE TableName = 'FactSales';

        DROP TABLE #DeltaStage;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        INSERT INTO dbo.ETL_Error_Log (ProcedureName, ErrorNumber, ErrorSeverity, ErrorState, ErrorLine, ErrorMessage)
        VALUES (ERROR_PROCEDURE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE(), ERROR_MESSAGE());

        THROW;
    END CATCH
END;
GO
