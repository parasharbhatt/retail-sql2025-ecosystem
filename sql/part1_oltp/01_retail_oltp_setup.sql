-- ============================================================================
-- PART 1: TASK-1 OLTP LAYER (Retail_OLTP)
-- ============================================================================
USE master;
GO

IF DB_ID('Retail_OLTP') IS NOT NULL
BEGIN
    ALTER DATABASE Retail_OLTP SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Retail_OLTP;
END;
GO

CREATE DATABASE Retail_OLTP;
GO

USE Retail_OLTP;
GO

-- (ii) Create OLTP Data Tables
IF OBJECT_ID('dbo.Customers', 'U') IS NULL
CREATE TABLE dbo.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100),
    City NVARCHAR(50),
    Region NVARCHAR(50),
    LastModified DATETIME2(7) NOT NULL CONSTRAINT DF_Customers_LastModified DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('dbo.Products', 'U') IS NULL
CREATE TABLE dbo.Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100),
    Category NVARCHAR(50),
    StandardCost DECIMAL(18,2),
    ListPrice DECIMAL(18,2),
    LastModified DATETIME2(7) NOT NULL CONSTRAINT DF_Products_LastModified DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('dbo.SalesHeader', 'U') IS NULL
CREATE TABLE dbo.SalesHeader (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderDateTimeUtc DATETIME2(7) NOT NULL,
    OrderDate AS CONVERT(DATE, OrderDateTimeUtc) PERSISTED,
    CustomerID INT FOREIGN KEY REFERENCES Customers(CustomerID),
    LastModified DATETIME2(7) NOT NULL CONSTRAINT DF_SalesHeader_LastModified DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('dbo.SalesDetail', 'U') IS NULL
CREATE TABLE dbo.SalesDetail (
    OrderDetailID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT FOREIGN KEY REFERENCES SalesHeader(OrderID),
    ProductID INT FOREIGN KEY REFERENCES Products(ProductID),
    Quantity INT,
    UnitPrice DECIMAL(18,2),
    LastModified DATETIME2(7) NOT NULL CONSTRAINT DF_SalesDetail_LastModified DEFAULT SYSUTCDATETIME()
);
GO

CREATE OR ALTER TRIGGER dbo.trg_Customers_SetLastModified
ON dbo.Customers
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(LastModified) RETURN;

    UPDATE c
    SET LastModified = SYSUTCDATETIME()
    FROM dbo.Customers AS c
    INNER JOIN inserted AS i ON i.CustomerID = c.CustomerID;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_Products_SetLastModified
ON dbo.Products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(LastModified) RETURN;

    UPDATE p
    SET LastModified = SYSUTCDATETIME()
    FROM dbo.Products AS p
    INNER JOIN inserted AS i ON i.ProductID = p.ProductID;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_SalesHeader_SetLastModified
ON dbo.SalesHeader
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(LastModified) RETURN;

    UPDATE h
    SET LastModified = SYSUTCDATETIME()
    FROM dbo.SalesHeader AS h
    INNER JOIN inserted AS i ON i.OrderID = h.OrderID;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_SalesDetail_SetLastModified
ON dbo.SalesDetail
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(LastModified) RETURN;

    UPDATE d
    SET LastModified = SYSUTCDATETIME()
    FROM dbo.SalesDetail AS d
    INNER JOIN inserted AS i ON i.OrderDetailID = d.OrderDetailID;
END;
GO

-- (iii) Add 100 records for Customers and Products Table
SET NOCOUNT ON;
DECLARE @i INT = 1;
WHILE @i <= 100
BEGIN
    INSERT INTO Customers (CustomerName, City, Region)
    VALUES (
        CONCAT('Customer_', @i),
        CHOOSE((@i % 4) + 1, 'Toronto', 'Vancouver', 'Montreal', 'Calgary'),
        CHOOSE((@i % 4) + 1, 'ON', 'BC', 'QC', 'AB')
    );

    DECLARE @BasePrice DECIMAL(18,2) = CAST((RAND() * 200) + 10 AS DECIMAL(18,2));
    INSERT INTO Products (ProductName, Category, StandardCost, ListPrice)
    VALUES (
        CONCAT('Product SKU-', @i),
        CHOOSE((@i % 3) + 1, 'Bikes', 'Accessories', 'Clothing'),
        @BasePrice,
        CAST(@BasePrice * 1.4 AS DECIMAL(18,2))
    );

    SET @i = @i + 1;
END;
GO

-- (iv) Generate 3 Years of Transactional History (~1,500 Orders) with realistic ListPrice lookup
DECLARE @StartDate DATE = DATEADD(YEAR, -3, CAST(SYSUTCDATETIME() AS DATE));
DECLARE @CurrentDate DATE = @StartDate;
DECLARE @OrderDateTimeUtc DATETIME2(7);

WHILE @CurrentDate <= CAST(SYSUTCDATETIME() AS DATE)
BEGIN
    IF RAND() > 0.3
    BEGIN
        DECLARE @OrderID INT;
        DECLARE @ProductID INT = CAST((RAND() * 99) + 1 AS INT);
        DECLARE @ProductListPrice DECIMAL(18,2);

        -- Fetch the product's actual ListPrice
        SELECT @ProductListPrice = ListPrice
        FROM dbo.Products
        WHERE ProductID = @ProductID;

        SET @OrderDateTimeUtc = DATEADD(
            SECOND,
            CAST(RAND() * 86400 AS INT),
            CONVERT(DATETIME2(7), @CurrentDate)
        );

        INSERT INTO dbo.SalesHeader (OrderDateTimeUtc, CustomerID)
        VALUES (@OrderDateTimeUtc, CAST((RAND() * 99) + 1 AS INT));

        SET @OrderID = SCOPE_IDENTITY();

        INSERT INTO dbo.SalesDetail (OrderID, ProductID, Quantity, UnitPrice)
        VALUES (@OrderID, @ProductID, CAST((RAND() * 3) + 1 AS INT), @ProductListPrice);
    END;
    SET @CurrentDate = DATEADD(DAY, 1, @CurrentDate);
END;
GO

