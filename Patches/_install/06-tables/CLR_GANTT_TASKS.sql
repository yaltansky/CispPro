/****** Object:  Table [CLR_GANTT_TASKS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[CLR_GANTT_TASKS]') AND type in (N'U'))
BEGIN
CREATE TABLE [CLR_GANTT_TASKS](
	[GANTT_ID] [int] NOT NULL,
	[PARENT_ID] [int] NULL,
	[TASK_ID] [int] NOT NULL,
	[DURATION] [float] NULL,
	[PROGRESS] [float] NULL,
	[D_TO_FACT] [datetime] NULL,
	[D_AFTER] [datetime] NULL,
	[D_BEFORE] [datetime] NULL,
	[HAS_CHILDS] [bit] NULL,
	[D_INITIAL] [datetime] NULL,
	[DURATION_BUFFER_MAX] [int] NULL,
	[GROUP_ID] [int] NULL,
	[D_FINAL] [date] NULL,
PRIMARY KEY CLUSTERED 
(
	[GANTT_ID] ASC,
	[TASK_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_CLR_GANTT_TASKS_GANTT_ID]') AND parent_object_id = OBJECT_ID(N'[CLR_GANTT_TASKS]'))
ALTER TABLE [CLR_GANTT_TASKS]  WITH CHECK ADD  CONSTRAINT [FK_CLR_GANTT_TASKS_GANTT_ID] FOREIGN KEY([GANTT_ID])
REFERENCES [CLR_GANTTS] ([GANTT_ID])
ON DELETE CASCADE
GO
IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_CLR_GANTT_TASKS_GANTT_ID]') AND parent_object_id = OBJECT_ID(N'[CLR_GANTT_TASKS]'))
ALTER TABLE [CLR_GANTT_TASKS] CHECK CONSTRAINT [FK_CLR_GANTT_TASKS_GANTT_ID]
GO
