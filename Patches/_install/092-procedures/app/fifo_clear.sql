if object_id('fifo_clear') is not null drop proc fifo_clear
go
create procedure fifo_clear
	@fifoId [uniqueidentifier]
WITH EXECUTE AS CALLER
AS
EXTERNAL NAME [Application.CLR].[UserDefinedFunctions].[FifoClear]
GO
