
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TALKS_HISTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [TALKS_HISTS](
	[PARENT_ID] [int] NULL,
	[HIST_ID] [int] IDENTITY(1,1) NOT NULL,
	[BODY] [varchar](max) NULL,
	[IS_PRIVATE] [bit] NOT NULL DEFAULT ((0)),
	[STATUS_ID] [int] NOT NULL DEFAULT ((0)),
	[MOL_ID] [int] NOT NULL DEFAULT ((-25)),
	[HAS_FILES] [bit] NULL,
	[D_ADD] [datetime] NOT NULL DEFAULT (getdate()),
	[D_UPDATE] [datetime] NOT NULL DEFAULT (getdate()),
PRIMARY KEY CLUSTERED 
(
	[HIST_ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_TALKS_HISTS_TALK_ID]') AND parent_object_id = OBJECT_ID(N'[TALKS_HISTS]'))
ALTER TABLE [TALKS_HISTS]  WITH CHECK ADD  CONSTRAINT [FK_TALKS_HISTS_TALK_ID] FOREIGN KEY([PARENT_ID])
REFERENCES [TALKS] ([TALK_ID])
ON DELETE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_TALKS_HISTS_TALK_ID]') AND parent_object_id = OBJECT_ID(N'[TALKS_HISTS]'))
ALTER TABLE [TALKS_HISTS] CHECK CONSTRAINT [FK_TALKS_HISTS_TALK_ID]
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_talks_hist]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_talks_hist] on [TALKS_HISTS]
for insert, update
as
begin

	set nocount on;

	if update(body)
	begin
		update x
		set last_hist_id = i.hist_id
		from talks x
			inner join inserted i on i.parent_id = x.talk_id
		where i.body is not null

		update x
		set count_unreads = count_unreads + 1
		from talks_mols x
			inner join inserted i on i.parent_id = x.talk_id and i.mol_id <> x.mol_id
		where i.body is not null
	end

end
' 
GO
