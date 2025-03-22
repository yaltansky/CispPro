USE CISP_SHARED
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[OPTIONS]') AND type in (N'U'))
BEGIN
CREATE TABLE [OPTIONS](
	[O_GROUP] [varchar](32) NULL,
	[O_PARENT] [varchar](32) NULL,
	[O_KEY] [varchar](32) NULL,
	[O_NAME] [varchar](50) NULL,
	[O_TYPE] [varchar](50) NULL,
	[O_TYPE_PARAM] [varchar](500) NULL,
	[O_REQUIRED] [bit] NULL,
	[O_READONLY] [bit] NULL,
	[O_DEFAULT] [bit] NULL,
	[O_FLEX] [varchar](32) NULL,
	[O_CSS] [varchar](100) NULL,
	[O_HINT] [varchar](max) NULL,
	[O_TOOLTIP] [varchar](max) NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [PK_OPTIONS] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO
