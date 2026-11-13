-- ============================================================================
-- PART 1: TASK-1 OLTP LAYER (Retail_OLTP)
-- ============================================================================
IF DB_ID('Retail_OLTP') IS NULL
BEGIN
    CREATE DATABASE Retail_OLTP;
END;
GO

USE Retail_OLTP;
GO

-- (ii) Create OLTP Data Tables
IF OBJECT_ID('dbo.Customers', 'U') IS NULL
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100),
    City NVARCHAR(50),
    Region NVARCHAR(50),
    LastModified DATETIME2 DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('dbo.Products', 'U') IS NULL
CREATE TABLE Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100),
    Category NVARCHAR(50),
    StandardCost DECIMAL(18,2),
    ListPrice DECIMAL(18,2),
    LastModified DATETIME2 DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('dbo.SalesHeader', 'U') IS NULL
CREATE TABLE SalesHeader (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    OrderDate DATE,
    CustomerID INT FOREIGN KEY REFERENCES Customers(CustomerID),
    LastModified DATETIME2 DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('dbo.SalesDetail', 'U') IS NULL
CREATE TABLE SalesDetail (
    OrderDetailID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT FOREIGN KEY REFERENCES SalesHeader(OrderID),
    ProductID INT FOREIGN KEY REFERENCES Products(ProductID),
    Quantity INT,
    UnitPrice DECIMAL(18,2),
    LastModified DATETIME2 DEFAULT SYSUTCDATETIME()
);
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

-- (iv) Generate 3 Years of Transactional History (~1,500 Orders)
DECLARE @StartDate DATE = DATEADD(YEAR, -3, CAST(SYSUTCDATETIME() AS DATE));
DECLARE @CurrentDate DATE = @StartDate;
WHILE @CurrentDate <= CAST(SYSUTCDATETIME() AS DATE)
BEGIN
    IF RAND() > 0.3 -- Randomly skip some days to look like natural retail patterns
    BEGIN
        INSERT INTO SalesHeader (OrderDate, CustomerID)
        VALUES (@CurrentDate, CAST((RAND() * 99) + 1 AS INT));

        INSERT INTO SalesDetail (OrderID, ProductID, Quantity, UnitPrice)
        VALUES (SCOPE_IDENTITY(), CAST((RAND() * 99) + 1 AS INT), CAST((RAND() * 3) + 1 AS INT), 50.00);
    END;
    SET @CurrentDate = DATEADD(DAY, 1, @CurrentDate);
END;
GO
