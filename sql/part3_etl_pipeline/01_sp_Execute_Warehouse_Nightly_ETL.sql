-- ============================================================================
-- PART 3: TASK-2 (v) COMPLETE ETL ORCHESTRATION PIPELINE
-- ============================================================================
USE Retail_DW;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Execute_Warehouse_Nightly_ETL
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
            Region NVARCHAR(50),
            EffectiveFrom DATETIME2(7)
        );

        DECLARE @ProductChanges TABLE (
            MergeAction NVARCHAR(10),
            BusinessKey INT,
            ProductName NVARCHAR(100),
            Category NVARCHAR(50),
            ListPrice DECIMAL(18,2),
            EffectiveFrom DATETIME2(7)
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
            Target.CustomerName IS DISTINCT FROM Source.CustomerName
            OR Target.City IS DISTINCT FROM Source.City
            OR Target.Region IS DISTINCT FROM Source.Region
        ) THEN
            UPDATE SET Target.ValidTo = Source.LastModified, Target.IsCurrent = 0
        WHEN NOT MATCHED THEN
            INSERT (CustomerID, CustomerName, City, Region, ValidFrom, ValidTo, IsCurrent)
            VALUES (Source.CustomerID, Source.CustomerName, Source.City, Source.Region, @InitialValidFrom, @MaxExpiry, 1)
        OUTPUT $action, Source.CustomerID, Source.CustomerName, Source.City, Source.Region, Source.LastModified
            INTO @CustomerChanges (MergeAction, BusinessKey, CustomerName, City, Region, EffectiveFrom);

        INSERT INTO dbo.DimCustomers (CustomerID, CustomerName, City, Region, ValidFrom, ValidTo, IsCurrent)
        SELECT BusinessKey, CustomerName, City, Region, EffectiveFrom, @MaxExpiry, 1
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
            Target.ProductName IS DISTINCT FROM Source.ProductName
            OR Target.Category IS DISTINCT FROM Source.Category
            OR Target.ListPrice IS DISTINCT FROM Source.ListPrice
        ) THEN
            UPDATE SET Target.ValidTo = Source.LastModified, Target.IsCurrent = 0
        WHEN NOT MATCHED THEN
            INSERT (ProductID, ProductName, Category, ListPrice, ValidFrom, ValidTo, IsCurrent)
            VALUES (Source.ProductID, Source.ProductName, Source.Category, Source.ListPrice, @InitialValidFrom, @MaxExpiry, 1)
        OUTPUT $action, Source.ProductID, Source.ProductName, Source.Category, Source.ListPrice, Source.LastModified
            INTO @ProductChanges (MergeAction, BusinessKey, ProductName, Category, ListPrice, EffectiveFrom);

        INSERT INTO dbo.DimProducts (ProductID, ProductName, Category, ListPrice, ValidFrom, ValidTo, IsCurrent)
        SELECT BusinessKey, ProductName, Category, ListPrice, EffectiveFrom, @MaxExpiry, 1
        FROM @ProductChanges
        WHERE MergeAction = 'UPDATE';

        UPDATE dbo.DW_Watermarks SET LastRunDateTime = @ExecutionTime WHERE TableName = 'DimProducts';

        ---------------------------------------------------------------------------------
        -- 3. INCREMENTAL FACT PROCESSING WITH POINT-IN-TIME SURROGATE KEY JOIN PATTERN
        ---------------------------------------------------------------------------------
        SELECT
            d.OrderDetailID, h.OrderID, h.OrderDateTimeUtc, h.CustomerID, d.ProductID, d.Quantity, d.UnitPrice
        INTO #DeltaStage
        FROM Retail_OLTP.dbo.SalesDetail d
        JOIN Retail_OLTP.dbo.SalesHeader h ON d.OrderID = h.OrderID
        WHERE h.LastModified > (SELECT LastRunDateTime FROM DW_Watermarks WHERE TableName = 'FactSales')
           OR d.LastModified > (SELECT LastRunDateTime FROM DW_Watermarks WHERE TableName = 'FactSales');

        -- Clear down existing fact entries to ensure idempotency (no duplicates)
        DELETE FROM dbo.FactSales WHERE OrderDetailID IN (SELECT OrderDetailID FROM #DeltaStage);

        IF EXISTS (
            SELECT 1
            FROM #DeltaStage AS stg
            OUTER APPLY (
                SELECT COUNT_BIG(*) AS MatchCount
                FROM dbo.DimCustomers AS dc
                WHERE dc.CustomerID = stg.CustomerID
                  AND stg.OrderDateTimeUtc >= dc.ValidFrom
                  AND stg.OrderDateTimeUtc < dc.ValidTo
            ) AS customerMatch
            WHERE customerMatch.MatchCount <> 1
        )
        BEGIN
            ;THROW 51001, 'Each staged sale must match exactly one customer dimension version.', 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM #DeltaStage AS stg
            OUTER APPLY (
                SELECT COUNT_BIG(*) AS MatchCount
                FROM dbo.DimProducts AS dp
                WHERE dp.ProductID = stg.ProductID
                  AND stg.OrderDateTimeUtc >= dp.ValidFrom
                  AND stg.OrderDateTimeUtc < dp.ValidTo
            ) AS productMatch
            WHERE productMatch.MatchCount <> 1
        )
        BEGIN
            ;THROW 51002, 'Each staged sale must match exactly one product dimension version.', 1;
        END;

        -- Use half-open validity intervals so a fact at the exact change time maps to the new version.
        INSERT INTO dbo.FactSales (OrderDetailID, OrderID, OrderDateTimeUtc, CustomerKey, ProductKey, Quantity, UnitPrice, SalesAmount)
        SELECT
            stg.OrderDetailID,
            stg.OrderID,
            stg.OrderDateTimeUtc,
            dc.CustomerKey,
            dp.ProductKey,
            stg.Quantity,
            stg.UnitPrice,
            (stg.Quantity * stg.UnitPrice)
        FROM #DeltaStage stg
        INNER JOIN dbo.DimCustomers dc
            ON stg.CustomerID = dc.CustomerID
           AND stg.OrderDateTimeUtc >= dc.ValidFrom
           AND stg.OrderDateTimeUtc < dc.ValidTo
        INNER JOIN dbo.DimProducts dp
            ON stg.ProductID = dp.ProductID
           AND stg.OrderDateTimeUtc >= dp.ValidFrom
           AND stg.OrderDateTimeUtc < dp.ValidTo;

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
