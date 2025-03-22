
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FIN_GOALS_MOLS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FIN_GOALS_MOLS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[FIN_GOAL_ID] [int] NOT NULL,
	[MOL_ID] [int] NOT NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[FOLDER_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO
