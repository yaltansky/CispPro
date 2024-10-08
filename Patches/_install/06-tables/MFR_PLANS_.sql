/****** Object:  Table [MFR_PLANS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_PLANS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_PLANS](
	[PLAN_ID] [int] IDENTITY(1,1) NOT NULL,
	[FOLDER_ID] [int] NULL,
	[SUBJECT_ID] [int] NULL,
	[NUMBER] [varchar](50) NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[STATUS_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[D_CALC_LINKS] [datetime] NULL,
	[CALENDAR_ID] [int] NULL,
	[PROJECT_TASK_ID] [int] NULL,
	[MOL_DIRECTOR_ID] [int] NULL,
	[MOL_MFR_DIRECTOR_ID] [int] NULL,
	[MOL_DISPATCH_ID] [int] NULL,
	[CALC_MODE_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[PLAN_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

