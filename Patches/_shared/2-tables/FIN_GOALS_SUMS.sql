
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FIN_GOALS_SUMS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FIN_GOALS_SUMS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[FIN_GOAL_ID] [int] NULL,
	[MOL_ID] [int] NULL,
	[GROUP_ID] [varchar](32) NULL,
	[FOLDER_ID] [int] NULL,
	[ARTICLE_ID] [int] NULL,
	[BUDGET_ID] [int] NULL,
	[EXCLUDED] [bit] NULL DEFAULT ((0)),
	[PARENT_ID] [int] NULL,
	[NODE_ID] [int] NULL,
	[NAME] [nvarchar](250) NULL,
	[HAS_CHILDS] [bit] NULL DEFAULT ((0)),
	[NODE] [hierarchyid] NULL,
	[LEVEL_ID] [int] NULL,
	[IS_DELETED] [bit] NULL,
	[SORT_ID] [float] NULL,
	[VALUE_START] [decimal](18, 2) NULL,
	[VALUE_IN] [decimal](18, 2) NULL,
	[VALUE_OUT] [decimal](18, 2) NULL,
	[VALUE_END] [decimal](18, 2) NULL,
	[VALUE_IN_EXCL] [decimal](18, 2) NULL,
	[VALUE_OUT_EXCL] [decimal](18, 2) NULL,
	[GOAL_ACCOUNT_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[FIN_GOALS_SUMS]') AND name = N'IX_FIN_GOALS_SUMS_NODE')
CREATE NONCLUSTERED INDEX [IX_FIN_GOALS_SUMS_NODE] ON [FIN_GOALS_SUMS]
(
	[FIN_GOAL_ID] ASC,
	[MOL_ID] ASC,
	[GROUP_ID] ASC,
	[NODE_ID] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_fin_goals_sums]'))
EXEC sp_executesql @statement = N'
create trigger [tu_fin_goals_sums] on [FIN_GOALS_SUMS]
for update as
begin
	
	set nocount on;

	if update(excluded)
	begin
		delete x 
		from fin_GOals_meta_excludes x
			join inserted i on i.folder_id = x.folder_id and x.budget_id = i.budget_id
		where i.excluded = 0

		insert into fin_GOals_meta_excludes (folder_id, budget_id)
		select distinct folder_id, budget_id
		from inserted i
		where not exists(select 1 from fin_GOals_meta_excludes where folder_id = i.folder_id and budget_id = i.budget_id)
			and i.excluded = 1
	end

end' 
GO
