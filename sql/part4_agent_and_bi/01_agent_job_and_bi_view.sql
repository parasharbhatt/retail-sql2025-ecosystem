-- ============================================================================
-- PART 4: TASK-2 (vi) SQL SERVER AGENT JOB & (vii) POWER BI PRESENTATION VIEW
-- ============================================================================

-- (vi) Automated SQL Server Agent Execution Definition (Idempotent Guarded)
USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'DW_Nightly_Orchestration_Pipeline')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'DW_Nightly_Orchestration_Pipeline', @delete_unused_schedule = 1;
END;
GO

EXEC sp_add_job
    @job_name = N'DW_Nightly_Orchestration_Pipeline',
    @enabled = 1,
    @description = N'Safely transforms transactional records to star schema format using SCD Type 2 tracking and custom surrogate keys.';

EXEC sp_add_jobstep
    @job_name = N'DW_Nightly_Orchestration_Pipeline',
    @step_name = N'Execute_ETL_Stored_Procedure',
    @subsystem = N'TSQL',
    @command = N'EXEC sp_Execute_Warehouse_Nightly_ETL;',
    @database_name = N'Retail_DW',
    @on_success_action = 1; -- Quit with reporting success

EXEC sp_add_jobschedule
    @job_name = N'DW_Nightly_Orchestration_Pipeline',
    @name = N'Daily_2AM_Execution',
    @freq_type = 4,              -- Daily configuration
    @freq_interval = 1,          -- Every 1 day
    @active_start_time = 020000; -- Formatted as HHMMSS

EXEC sp_add_jobserver
    @job_name = N'DW_Nightly_Orchestration_Pipeline',
    @server_name = N'(local)';
GO

-- (vii) Power BI Verification View
USE Retail_DW;
GO

CREATE OR ALTER VIEW vPresentation_SalesFact AS
SELECT
    f.SalesKey, f.OrderID, f.OrderDate, f.Quantity, f.UnitPrice, f.SalesAmount,
    c.CustomerName, c.City, c.Region,
    p.ProductName, p.Category
FROM FactSales f
JOIN DimCustomers c ON f.CustomerKey = c.CustomerKey   -- Joins directly on the correct surrogate version
JOIN DimProducts p ON f.ProductKey = p.ProductKey;     -- Extracted historical item version
GO

