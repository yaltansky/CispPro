IF NOT EXISTS(SELECT 1 FROM SYS.TYPES WHERE NAME = 'FIFO_RESPONSE')
CREATE TYPE [FIFO_RESPONSE] AS TABLE(
	[LEFT_ROW_ID] [int] NULL,
	[RIGHT_ROW_ID] [int] NULL,
	[VALUE] [float] NULL
)
GO
