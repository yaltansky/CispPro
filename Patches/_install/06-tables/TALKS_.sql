/****** Object:  Table [TALKS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TALKS]') AND type in (N'U'))
BEGIN
CREATE TABLE [TALKS](
	[TALK_ID] [int] IDENTITY(1,1) NOT NULL,
	[KEY] [varchar](255) NOT NULL,
	[SUBJECT] [varchar](max) NULL,
	[BODY] [varchar](max) NULL,
	[STATUS_ID] [int] NOT NULL DEFAULT ((0)),
	[ACCOUNT_LEVEL_ID] [int] NULL,
	[MOL_ID] [int] NOT NULL DEFAULT ((-25)),
	[D_ADD] [datetime] NOT NULL DEFAULT (getdate()),
	[D_UPDATE] [datetime] NOT NULL DEFAULT (getdate()),
	[LAST_HIST_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[TALK_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Trigger [ti_talks]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_talks]'))
EXEC dbo.sp_executesql @statement = N'
create trigger [ti_talks] on [TALKS]
for insert
as
begin

	set nocount on;

	insert into talks_mols(talk_id, mol_id)
	select talk_id, mol_id
	from inserted

end' 
GO
