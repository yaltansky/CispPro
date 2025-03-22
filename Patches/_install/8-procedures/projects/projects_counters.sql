if exists(select 1 from sys.objects where name = 'projects_counters')
	drop proc projects_counters
go
create proc projects_counters
	@mol_id int
as
begin

	set nocount on;

	declare @themes table(theme_id int primary key, name varchar(50))
		insert into @themes values
			(1, 'Куратор проектов'),
			(2, 'Руководитель проектов'),
			(3, 'Администратор проектов'),
			(4, 'Участник проектов')

	create table #projects(project_id int primary key, theme_id int)
	insert into #projects exec projects_counters;10 @mol_id = @mol_id

	-- result
	select * from (
		select
			theme_id,
			name,
			(select count(*) from #projects where theme_id = x.theme_id) as counts
		from @themes x
		) c
	 where counts > 0
end
GO

create proc projects_counters;2
	@mol_id int,
	@theme_id int
as
begin

	set nocount on;

	create table #projects(project_id int primary key, theme_id int)
	insert into #projects exec projects_counters;10 @mol_id = @mol_id

	select project_id from #projects where theme_id = @theme_id
end
go

create proc projects_counters;10
	@mol_id int
as
begin

	set nocount on;

	declare @projects table (project_id int primary key, theme_id int)

	insert into @projects
		select project_id, 1 from projects where status_id between 1 and 4 and curator_id = @mol_id

	insert into @projects
		select project_id, 2 from projects where status_id between 1 and 4 and chief_id = @mol_id
			and project_id not in (select project_id from @projects)

	insert into @projects
		select project_id, 3 from projects where status_id between 1 and 4 and admin_id = @mol_id
			and project_id not in (select project_id from @projects)

	insert into @projects
		select project_id, 4 from projects x where status_id between 1 and 4
			and exists(select 1 from projects_mols where project_id = x.project_id and mol_id = @mol_id)
			and project_id not in (select project_id from @projects)

	select project_id, theme_id from @projects
end
go