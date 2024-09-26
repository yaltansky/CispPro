if object_id('project_calc_indicators') is not null drop proc project_calc_indicators
go
CREATE PROCEDURE [project_calc_indicators]
	@project_id [int]
WITH EXECUTE AS CALLER
AS
EXTERNAL NAME [Application.CLR].[StoredProcedures].[project_calc_indicators]
GO
