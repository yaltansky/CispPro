
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_RESOURCES]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_RESOURCES](
	[RESOURCE_ID] [int] IDENTITY(1,1) NOT NULL,
	[PARENT_ID] [int] NULL,
	[NAME] [varchar](100) NOT NULL,
	[AGGREGATION_ID] [int] NULL DEFAULT ((1)),
	[DISTRIBUTION_ID] [int] NULL DEFAULT ((1)),
	[DESCRIPTION] [varchar](max) NULL,
	[HAS_CHILDS] [bit] NULL DEFAULT ((0)),
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[MOL_ID] [int] NOT NULL,
	[ADD_DATE] [datetime] NOT NULL DEFAULT (getdate()),
	[LIMIT_Q] [decimal](18, 3) NULL,
	[NODE] [hierarchyid] NULL,
	[PRICE] [decimal](18, 2) NULL,
	[TYPE_ID] [int] NULL,
	[EXTERN_ID] [varchar](32) NULL,
PRIMARY KEY CLUSTERED 
(
	[RESOURCE_ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PROJECTS_RESOURCES]') AND name = N'IX_PROJECTS_RESOURCES')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PROJECTS_RESOURCES] ON [PROJECTS_RESOURCES]
(
	[NAME] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiud_projects_resources]'))
EXEC sp_executesql @statement = N'
create trigger [tiud_projects_resources] on [PROJECTS_RESOURCES]
for insert, update, delete
as
begin

	set nocount on;

	declare @resources table(resource_id int)

	insert into @resources(resource_id)
	select distinct parent_id 
	from (
		select parent_id from inserted union all select parent_id from deleted
		) u
	where parent_id is not null

	update p
	set has_childs = case when exists(select 1 from projects_resources where parent_id = p.resource_id) then 1 else 0 end
	from projects_resources p
	where p.resource_id in (select resource_id from @resources)

	update p
	set sort_id = isnull((select max(sort_id) from projects_resources), 1)
	from projects_resources p
	where p.resource_id in (select resource_id from inserted)
		and p.sort_id is null
	
end
' 
GO
