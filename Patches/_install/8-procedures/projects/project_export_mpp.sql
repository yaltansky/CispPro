if object_id('project_export_mpp') is not null drop proc project_export_mpp
go
-- exec project_export_mpp 31977
create proc project_export_mpp
	@project_id int,
	@result_xml xml = null out
as
begin

	SET NOCOUNT ON;

	create table #dhx_tasks (
		project_id int,
		id int primary key,
		task_number int,
		predecessors varchar(max),
		text varchar(max),
		start_date datetime,
		end_date datetime,
		base_start datetime,
		base_end datetime,
		duration float,
		duration_buffer int,
		progress float,
		sortorder float,
		parent int,
		[type] varchar(16),
		[open] bit,
		is_critical bit,
		is_critical_label varchar(12),
		is_long bit,
		outline_level int,
		execute_level int
		)			
			
	-- #dhx_tasks
	insert into #dhx_tasks
	exec dhx_gantt_tasks_view @project_id = @project_id

	-- #search
	create table #search (task_id int primary key)
	insert into #search exec project_tasks_search @project_id = @project_id, @extra_id = 100

	-- @tasks
	create table #tasks (
		Id int index ix_tasks,
		UID int primary key,
		Name varchar(max),
		Summary int,
		Critical bit,
		Start datetime,
		Finish datetime,
		ActualDuration varchar(20),
		Duration varchar(20),
		RemainingDuration varchar(20),
		OutlineLevel int
		)
	
	insert into #tasks(Id, UID, Name, Summary, Critical, Start, Finish, ActualDuration, RemainingDuration, OutlineLevel)
	select task_id, UID, Name, Summary, Critical, Start, Finish, ActualDuration, RemainingDuration, OutlineLevel
	from (
		select
			t.task_id,
			t.task_number as 'UID',
			t.name as 'Name',
			case when t.has_childs = 1 then 1 else 0 end as 'Summary',
			dhx.is_critical as 'Critical',
			isnull(t.d_from_fact, dhx.start_date) as 'Start',
			isnull(t.d_to_fact, dhx.end_date) as 'Finish',
			'PT' + cast(cast(dhx.duration * dhx.progress * 8 as int) as varchar) + 'H' as 'ActualDuration',
			'PT' + cast(cast(dhx.duration * (1 - dhx.progress) * 8 as int) as varchar) + 'H' as 'RemainingDuration',
			t.outline_level as 'OutlineLevel'
		from projects_tasks t
			join #dhx_tasks dhx on dhx.id = t.task_id
			join #search s on s.task_id = t.task_id
		) t

	declare @content nvarchar(max)

	declare @links table(target_id int index ix_target, source_number int)
	insert into @links(target_id, source_number) select target_id, source_number from v_projects_tasks_links where project_id = @project_id

	set @result_xml = (
	select *
	from (
		select 			
			14 as 'SaveVersion',
			name as 'Title',
			d_from as 'StartDate',
			(
				select
					task.*,
					(
						select PredecessorUID
						from (
							select source_number as 'PredecessorUID'
							from @links
							where target_id = task.Id
							) PredecessorLink
						for xml auto, type, elements
					)
				from #tasks Task
				order by uid
				for xml auto, type, elements
			) Tasks
		from projects
		where project_id = @project_id
		) Project
	for xml auto, type, elements
	)

	drop table #tasks, #search, #dhx_tasks;

    set @result_xml = replace(cast(@result_xml as varchar(max)), '<Project>', '<Project xmlns="http://schemas.microsoft.com/project">')
	select @result_xml
end
go
