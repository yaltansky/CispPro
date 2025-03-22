
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_TASKS_RACI]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_TASKS_RACI](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[TASK_ID] [int] NULL,
	[MOL_ID] [int] NULL,
	[RACI] [varchar](10) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PROJECTS_TASKS_RACI]') AND name = N'IX_PROJECTS_TASKS_RACI')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PROJECTS_TASKS_RACI] ON [PROJECTS_TASKS_RACI]
(
	[TASK_ID] ASC,
	[MOL_ID] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tid_projects_tasks_raci]'))
EXEC sp_executesql @statement = N'
create trigger [tid_projects_tasks_raci] on [PROJECTS_TASKS_RACI]
for INSERT, DELETE
as
begin

	set nocount on;

	update t
	set count_raci = 
			case 
				when r.count_raci is not null then substring(r.count_raci, 1, len(r.count_raci) - 1)
			end
	from projects_tasks t
		left join (
			select
				t.task_id, (
					  case when r.raci is not null then r.raci + ''.'' else '''' end
					+ case when a.raci is not null then a.raci + ''.'' else '''' end
					+ case when c.raci is not null then c.raci + ''.'' else '''' end
					+ case when i.raci is not null then i.raci + ''.'' else '''' end
					) as count_raci
			from projects_tasks t
				left join (
					select task_id,  ''R'' + cast(count(*) as varchar) as raci from projects_tasks_raci where raci like ''%R%'' group by task_id
					) r on r.task_id = t.task_id
				left join (
					select task_id,  ''A'' + cast(count(*) as varchar) as raci from projects_tasks_raci where raci like ''%A%'' group by task_id
					) a on a.task_id = t.task_id
				left join (
					select task_id,  ''C'' + cast(count(*) as varchar) as raci from projects_tasks_raci where raci like ''%C%'' group by task_id
					) c on c.task_id = t.task_id
				left join (
					select task_id,  ''I'' + cast(count(*) as varchar) as raci from projects_tasks_raci where raci like ''%I%'' group by task_id
					) i on i.task_id = t.task_id
			where r.raci is not null or a.raci is not null  or c.raci is not null or i.raci is not null
		) r on r.task_id = t.task_id
	where t.task_id in (select distinct task_id from inserted union select task_id from deleted)

end
' 
GO
