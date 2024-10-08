/****** Object:  Table [MFR_PLACES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_PLACES]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_PLACES](
	[SUBJECT_ID] [int] NULL,
	[PLACE_ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](100) NULL,
	[NOTE] [varchar](max) NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[MAIN_ID] [int] NULL,
	[FULL_NAME] [varchar](250) NULL,
	[WORK_TYPE_ID] [int] NULL,
	[WORK_HOURS] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[PLACE_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Trigger [tiu_mfr_places]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_mfr_places]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tiu_mfr_places] on [MFR_PLACES]
for insert, update as
begin
	
	set nocount on;

	update mfr_places
	set full_name = substring(concat(name, ''-'', note), 1, 250)
	where place_id in (
		select place_id from inserted
		)

end' 
GO
