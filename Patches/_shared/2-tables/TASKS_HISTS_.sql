
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TASKS_HISTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [TASKS_HISTS](
	[HIST_ID] [int] IDENTITY(1,1) NOT NULL,
	[TASK_ID] [int] NOT NULL,
	[ACTION_NAME] [varchar](50) NOT NULL,
	[DESCRIPTION] [varchar](max) NULL,
	[MOL_ID] [int] NOT NULL,
	[TO_MOLS] [varchar](max) NULL,
	[TO_MOLS_IDS] [varchar](max) NULL,
	[DURATION] [int] NULL,
	[HAS_FILES] [bit] NULL DEFAULT ((0)),
	[D_ADD] [datetime] NULL DEFAULT (getdate()),
	[PARENT_ID] [int] NULL,
	[IS_PRIVATE] [bit] NOT NULL DEFAULT ((0)),
	[QUERY_STATUS_ID] [int] NULL,
	[QUERY_SOLUTION_ID] [int] NULL,
	[QUERY_SOLUTION_GRADES] [int] NULL,
	[BODY] [varchar](max) NULL,
	[BODY_CSS] [varchar](32) NULL,
	[ACTION_ID] [varchar](32) NULL,
	[TO_STATUS_ID] [int] NULL,
	[SILENCE] [bit] NULL,
CONSTRAINT [PK_TASKS_HISTS] PRIMARY KEY CLUSTERED 
(
	[HIST_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[TASKS_HISTS]') AND name = N'IX_TASKS_HISTS')
CREATE NONCLUSTERED INDEX [IX_TASKS_HISTS] ON [TASKS_HISTS]
(
	[TASK_ID] ASC,
	[MOL_ID] ASC
)
GO


IF not EXISTS (SELECT * FROM sys.fulltext_indexes fti WHERE fti.object_id = OBJECT_ID(N'[TASKS_HISTS]'))
CREATE FULLTEXT INDEX ON [TASKS_HISTS](
[BODY] LANGUAGE 'English', 
[DESCRIPTION] LANGUAGE 'English')
KEY INDEX [PK_TASKS_HISTS]ON ([CATALOG], FILEGROUP [PRIMARY])
WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM)
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_TASKS_HISTS_TASKS]') AND parent_object_id = OBJECT_ID(N'[TASKS_HISTS]'))
ALTER TABLE [TASKS_HISTS]  WITH CHECK ADD  CONSTRAINT [FK_TASKS_HISTS_TASKS] FOREIGN KEY([TASK_ID])
REFERENCES [TASKS] ([TASK_ID])
ON DELETE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_TASKS_HISTS_TASKS]') AND parent_object_id = OBJECT_ID(N'[TASKS_HISTS]'))
ALTER TABLE [TASKS_HISTS] CHECK CONSTRAINT [FK_TASKS_HISTS_TASKS]
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_tasks_hists]'))
EXEC sp_executesql @statement = N'create trigger [ti_tasks_hists] on [TASKS_HISTS]
for insert
as begin
 
	set nocount on;
	
	update x
	set update_mol_id = h.mol_id, update_date = h.d_add
	from tasks x
		join (
			select task_id, hist_id = max(hist_id)
			from tasks_hists
			group by task_id
		) xx on xx.task_id = x.task_id
		join tasks_hists h on h.hist_id = xx.hist_id
	where x.task_id in (select task_id from inserted)

end' 
GO
