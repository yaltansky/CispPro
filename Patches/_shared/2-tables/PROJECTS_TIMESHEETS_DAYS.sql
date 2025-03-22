
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_TIMESHEETS_DAYS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_TIMESHEETS_DAYS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[TIMESHEET_ID] [int] NOT NULL,
	[D_DOC] [datetime] NULL,
	[PLAN_H] [decimal](18, 2) NULL,
	[FACT_H] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
	[IS_DELETED] [bit] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[FIXED_DATE] [datetime] NULL,
	[FIXED_MOL_ID] [int] NULL,
	[EVENT_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

