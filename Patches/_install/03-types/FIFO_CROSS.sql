IF NOT EXISTS(SELECT 1 FROM SYS.TYPES WHERE NAME = 'FIFO_CROSS')
CREATE TYPE [FIFO_CROSS] AS TABLE(
	[ORDER_ID] [int] IDENTITY(1,1) NOT NULL,
	[LEFT_ROW_ID] [int] NULL,
	[RIGHT_ROW_ID] [int] NULL
)
GO
