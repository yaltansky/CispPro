USE CISP_SHARED
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[APP_IMPORTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[APP_IMPORTS](
	[GROUP_ID] [uniqueidentifier] NULL,
	[IMPORT_ID] [int] IDENTITY(1,1) NOT NULL,
	[IMPORT_TYPE] [varchar](32) NULL,
	[DBNAME] [varchar](64) NULL,
	[FOLDER_ID] [int] NULL,
	[OBJ_TYPE] [varchar](20) NULL,
	[RESULTS] [varchar](max) NULL,
	[ERRORS] [varchar](max) NULL,
	[ADD_DATE] [datetime] NOT NULL,
	[MOL_ID] [int] NULL,
  CONSTRAINT [PK__APP_IMPORTS] PRIMARY KEY CLUSTERED (
	  [IMPORT_ID] ASC
  )
)
END
GO
ALTER TABLE [dbo].[APP_IMPORTS] ADD DEFAULT (getdate()) FOR [ADD_DATE]
GO
