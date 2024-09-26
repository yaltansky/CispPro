if object_id('cyclogram_calc') is not null drop proc cyclogram_calc
GO
create procedure cyclogram_calc
	@gantt_id [int],
	@trace_allowed [bit]
WITH EXECUTE AS CALLER
AS
    EXTERNAL NAME [Application.CLR].[StoredProcedures].[cyclogram_calc]
GO
