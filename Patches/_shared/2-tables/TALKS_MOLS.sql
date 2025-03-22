
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TALKS_MOLS]') AND type in (N'U'))
BEGIN
CREATE TABLE [TALKS_MOLS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[TALK_ID] [int] NOT NULL,
	[MOL_ID] [int] NOT NULL,
	[IS_ONLINE] [bit] NOT NULL CONSTRAINT [DF__TALKS_MOL__IS_ON__458D4A32]  DEFAULT ((0)),
	[IS_DELETED] [bit] NOT NULL CONSTRAINT [DF__TALKS_MOL__IS_DE__622988E0]  DEFAULT ((0)),
	[COUNT_UNREADS] [int] NOT NULL CONSTRAINT [DF__TALKS_MOL__COUNT__631DAD19]  DEFAULT ((0)),
 CONSTRAINT [PK_TALKS_MOLS] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[TALKS_MOLS]') AND name = N'IX_TALKS_MOLS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_TALKS_MOLS] ON [TALKS_MOLS]
(
	[TALK_ID] ASC,
	[MOL_ID] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_TALKS_MOLS_TALK_ID]') AND parent_object_id = OBJECT_ID(N'[TALKS_MOLS]'))
ALTER TABLE [TALKS_MOLS]  WITH CHECK ADD  CONSTRAINT [FK_TALKS_MOLS_TALK_ID] FOREIGN KEY([TALK_ID])
REFERENCES [TALKS] ([TALK_ID])
ON DELETE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_TALKS_MOLS_TALK_ID]') AND parent_object_id = OBJECT_ID(N'[TALKS_MOLS]'))
ALTER TABLE [TALKS_MOLS] CHECK CONSTRAINT [FK_TALKS_MOLS_TALK_ID]
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_talks_mols_read]'))
EXEC sp_executesql @statement = N'create trigger [tu_talks_mols_read] on [TALKS_MOLS]
for update
as
begin

	set nocount on;

	update talks
	set status_id = 1
	where talk_id in (select talk_id from inserted where count_unreads > 0)

	update x
	set is_deleted = 0
	from talks_mols x
		inner join inserted i on i.talk_id = x.talk_id and i.mol_id = x.mol_id
	where i.count_unreads > 0

end
' 
GO
