/****** Object:  Table [ZIP_OBJS_FOLDERS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[ZIP_OBJS_FOLDERS]') AND type in (N'U'))
BEGIN
CREATE TABLE [ZIP_OBJS_FOLDERS](
	[FOLDER_ID] [int] NOT NULL,
	[KEYWORD] [varchar](32) NULL,
	[NAME] [varchar](128) NULL,
	[OBJ_TYPE] [varchar](8) NULL
) ON [PRIMARY]
END
GO

