if object_id('fifo_reminds') is not null  drop function fifo_reminds
go
CREATE FUNCTION [fifo_reminds](@fifoId [uniqueidentifier])
RETURNS  TABLE (
	[rq_row_id] [int] NULL,
	[rq_value] [float] NULL,
	[pv_row_id] [int] NULL,
	[pv_value] [float] NULL
) WITH EXECUTE AS CALLER
AS 
EXTERNAL NAME [Application.CLR].[UserDefinedFunctions].[FifoReminds]
GO
