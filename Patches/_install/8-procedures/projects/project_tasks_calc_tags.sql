if object_id('project_tasks_calc_tags') is not null drop proc project_tasks_calc_tags
go
create proc project_tasks_calc_tags
	@project_id int
as
begin

	set nocount on;

	declare @alltags varchar(max); set @alltags = ''

-- 	projects_tasks
	update projects_tasks
	set @alltags = @alltags + tags + ','
	where project_id = @project_id
		and tags is not null

	exec project_tasks_calc_tags;2 @project_id = @project_id, @type_id = 1, @alltags = @alltags
end
GO

create proc project_tasks_calc_tags;2
	@project_id int,
	@type_id int,
	@alltags varchar(max)
as
begin

	declare @tags table(name varchar(50))
	insert into @tags(name)
	select distinct item from dbo.str2rows(@alltags,',')
	where item is not null

	-- delete unused
	delete t
	from projects_tags t
	where project_id = @project_id
		and type_id = @type_id
		and not exists(select 1 from @tags where name = t.name)
	
	-- insert news
	insert into projects_tags(project_id, type_id, name)
	select @project_id, @type_id, name
	from @tags t
	where not exists(select 1 from projects_tags where project_id = @project_id and type_id = @type_id and name = t.name)
	
end