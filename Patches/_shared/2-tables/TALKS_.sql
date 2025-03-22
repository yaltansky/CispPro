
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
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_talks]'))
EXEC sp_executesql @statement = N'
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
