/****** Object:  Table [ZIP_OBJS_FOLDERS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[ZIP_OBJS_FOLDERS_DETAILS]') AND type in (N'U'))
BEGIN
CREATE TABLE [ZIP_OBJS_FOLDERS_DETAILS](
	[FOLDER_ID] [int] NOT NULL,
	[OBJ_TYPE] [varchar](8) NOT NULL,
	[OBJ_ID] [int] NOT NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL
) ON [PRIMARY]
END
GO

