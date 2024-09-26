/****** Object:  Table [PRODMETA_ATTRS_VALUES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PRODMETA_ATTRS_VALUES]') AND type in (N'U'))
BEGIN
CREATE TABLE [PRODMETA_ATTRS_VALUES](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[ATTR_ID] [int] NULL,
	[ATTR_VALUE] [varchar](max) NULL,
	[ATTR_VALUE_NUMBER] [float] NULL
)
END
GO

