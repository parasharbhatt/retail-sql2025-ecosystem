-- ============================================================================
-- PART 2: TASK-2 DW CORE LAYER (Retail_DW, Logging, Watermarks, SCD2, Indexes)
-- ============================================================================
USE master;
GO

IF DB_ID('Retail_DW') IS NOT NULL
BEGIN
    ALTER DATABASE Retail_DW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Retail_DW;
END;
GO

CREATE DATABASE Retail_DW;
GO

USE Retail_DW;
GO
-- (ii) Centralized Execution Error Logging Engine
IF OBJECT_ID('dbo.ETL_Error_Log', 'U') IS NULL
CREATE TABLE dbo.ETL_Error_Log (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    ProcedureName NVARCHAR(100),
    ErrorNumber INT,
    ErrorSeverity INT,
    ErrorState INT,
    ErrorLine INT,
    ErrorMessage NVARCHAR(MAX),
    LogDateTime DATETIME2 DEFAULT SYSUTCDATETIME()
);

-- (iii) High-Water Mark Tracking Table for Incremental Ingestion
IF OBJECT_ID('dbo.DW_Watermarks', 'U') IS NULL
CREATE TABLE dbo.DW_Watermarks (
    TableName VARCHAR(100) PRIMARY KEY,
    LastRunDateTime DATETIME2 NOT NULL
);

-- Seed baseline watermarks so the initial ETL run captures all OLTP records
MERGE dbo.DW_Watermarks AS Target
USING (VALUES
    ('DimCustomers', CAST('1900-01-01 00:00:00' AS DATETIME2)),
    ('DimProducts',  CAST('1900-01-01 00:00:00' AS DATETIME2)),
    ('FactSales',    CAST('1900-01-01 00:00:00' AS DATETIME2))
) AS Source (TableName, LastRunDateTime)
ON Target.TableName = Source.TableName
WHEN NOT MATCHED THEN
    INSERT (TableName, LastRunDateTime) VALUES (Source.TableName, Source.LastRunDateTime);
GO

-- (iv) Dimension and Fact Tables
IF OBJECT_ID('dbo.DimCustomers', 'U') IS NULL
CREATE TABLE dbo.DimCustomers (
    CustomerKey INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT, -- Business Key
    CustomerName NVARCHAR(100),
    City NVARCHAR(50),
    Region NVARCHAR(50),
    ValidFrom DATETIME2 NOT NULL,
    ValidTo DATETIME2 NOT NULL,
    IsCurrent BIT NOT NULL
);

IF OBJECT_ID('dbo.DimProducts', 'U') IS NULL
CREATE TABLE dbo.DimProducts (
    ProductKey INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT, -- Business Key
    ProductName NVARCHAR(100),
    Category NVARCHAR(50),
    ListPrice DECIMAL(18,2),
    ValidFrom DATETIME2 NOT NULL,
    ValidTo DATETIME2 NOT NULL,
    IsCurrent BIT NOT NULL
);

IF OBJECT_ID('dbo.FactSales', 'U') IS NULL
CREATE TABLE dbo.FactSales (
    SalesKey INT IDENTITY(1,1) PRIMARY KEY,
    OrderDetailID INT, -- Line item operational tracking check
    OrderID INT,
    OrderDateTimeUtc DATETIME2(7) NOT NULL,
    OrderDate AS CONVERT(DATE, OrderDateTimeUtc) PERSISTED,
    CustomerKey INT FOREIGN KEY REFERENCES DimCustomers(CustomerKey), -- SCD2 Link
    ProductKey INT FOREIGN KEY REFERENCES DimProducts(ProductKey),   -- SCD2 Link
    Quantity INT,
    UnitPrice DECIMAL(18,2),
    SalesAmount DECIMAL(18,2)
);
GO

-- Critical Indexing Infrastructure for Lookup Optimizations
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DimCustomers_Lookup' AND object_id = OBJECT_ID('dbo.DimCustomers'))
    CREATE NONCLUSTERED INDEX IX_DimCustomers_Lookup ON dbo.DimCustomers (CustomerID, ValidFrom, ValidTo);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DimProducts_Lookup' AND object_id = OBJECT_ID('dbo.DimProducts'))
    CREATE NONCLUSTERED INDEX IX_DimProducts_Lookup ON dbo.DimProducts (ProductID, ValidFrom, ValidTo);
GO

