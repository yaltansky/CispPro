/****** Object:  Table [FINDOCS_AZ]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FINDOCS_AZ]') AND type in (N'U'))
BEGIN
CREATE TABLE [FINDOCS_AZ](
	[MOL_ID] [int] NULL,
	[SUBJECT_ID] [int] NULL,
	[BUDGET_ID] [int] NULL,
	[ARTICLE_ID] [int] NULL,
	[INPUT_RUR] [decimal](18, 2) NULL,
	[OUTPUT_RUR] [decimal](18, 2) NULL,
	[FOLDER_ID] [int] NULL
) ON [PRIMARY]
END
GO
