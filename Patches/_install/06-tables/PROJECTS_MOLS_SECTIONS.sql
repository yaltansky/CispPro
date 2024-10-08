/****** Object:  Table [PROJECTS_MOLS_SECTIONS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_MOLS_SECTIONS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_MOLS_SECTIONS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PROJECT_ID] [int] NULL,
	[MOL_ID] [int] NULL,
	[SECTION_ID] [int] NULL,
	[A_READ] [tinyint] NULL,
	[A_UPDATE] [tinyint] NULL
) ON [PRIMARY]
END
GO
