USE CISP_SHARED
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[APP_EXPORTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [dbo].[APP_EXPORTS](
	[GROUP_ID] [uniqueidentifier] NULL,
	[EXPORT_ID] [int] IDENTITY(1,1) NOT NULL,
	[EXPORT_TYPE] [varchar](32) NULL,
	[DBNAME] [varchar](64) NULL,
	[FILE_NAME] [varchar](max) NULL,
	[FILE_URL] [varchar](max) NULL,
	[D_FROM] [date] NULL,
	[D_TO] [date] NULL,
	[FOLDER_ID] [int] NULL,
	[OBJ_TYPE] [varchar](20) NULL,
	[DATA] [xml] NULL,
	[RESULTS] [varchar](max) NULL,
	[ERRORS] [varchar](max) NULL,
	[ADD_DATE] [datetime] NOT NULL,
	[MOL_ID] [int] NULL,
  CONSTRAINT [PK__APP_EXPORTS] PRIMARY KEY CLUSTERED (
	  [EXPORT_ID] ASC
  )
)
END
GO
ALTER TABLE [dbo].[APP_EXPORTS] ADD DEFAULT (getdate()) FOR [ADD_DATE]
GO
