
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TREES]') AND type in (N'U'))
BEGIN
CREATE TABLE [TREES](
	[TYPE_ID] [int] NULL DEFAULT ((1)),
	[PARENT_ID] [int] NULL,
	[TREE_ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](max) NOT NULL,
	[DESCRIPTION] [varchar](max) NULL,
	[OBJ_TYPE] [varchar](8) NULL,
	[OBJ_ID] [int] NULL,
	[HAS_CHILDS] [bit] NULL DEFAULT ((0)),
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[NODE] [hierarchyid] NULL,
	[NODE_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[TREE_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_trees]'))
EXEC sp_executesql @statement = N'create trigger [ti_trees] on [TREES]
for insert
as begin
 
	set nocount on;

	update trees
	set node_id = tree_id
	where tree_id in (select tree_id from inserted)

end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiud_trees]'))
EXEC sp_executesql @statement = N'create trigger [tiud_trees] on [TREES]
for insert, update, delete
as
begin

	set nocount on;

	declare @trees table(tree_id int)

	insert into @trees(tree_id)
	select distinct parent_id 
	from (
		select parent_id from inserted union all select parent_id from deleted
		) u
	where parent_id is not null

	update p
	set has_childs = case when exists(select 1 from trees where parent_id = p.tree_id) then 1 else 0 end
	from trees p
	where p.tree_id in (select tree_id from @trees)

	update p
	set sort_id = isnull((select max(sort_id) from trees), 1)
	from trees p
	where p.tree_id in (select tree_id from inserted)
		and p.sort_id is null
	
end
' 
GO
