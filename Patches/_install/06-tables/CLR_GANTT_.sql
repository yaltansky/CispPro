/****** Object:  Table [CLR_GANTTS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[CLR_GANTTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [CLR_GANTTS](
	[GANTT_ID] [int] IDENTITY(1,1) NOT NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[D_TO_MIN] [datetime] NULL,
	[D_TO_FORECAST] [datetime] NULL,
	[D_TODAY] [datetime] NULL,
	[CALC_MODE_ID] [int] NULL,
	[CALENDAR_ID] [int] NULL,
	[ADD_DATE] [datetime] default getdate(),
	[ADD_MOL_ID] [int] NULL,
	[GROUP_ID] [uniqueidentifier] NULL,
PRIMARY KEY CLUSTERED 
(
	[GANTT_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
