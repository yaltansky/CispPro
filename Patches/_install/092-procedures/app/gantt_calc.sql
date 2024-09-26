if object_id('gantt_calc') is not null drop proc gantt_calc
go
CREATE PROCEDURE [gantt_calc]
	@gantt_id [int],
	@trace_allowed [bit]
WITH EXECUTE AS CALLER
AS
EXTERNAL NAME [Application.CLR].[StoredProcedures].[gantt_calc]
GO
