if object_id('budgets_calc_access') is not null drop proc budgets_calc_access
go
create proc budgets_calc_access
	@budget_id int = null,
    @project_id int = null,
	@projects app_pkids readonly,
	@echo bit = 0
as
begin

	set nocount on;

	declare @tid int; exec tracer_init 'budgets_calc_access', @trace_id = @tid out

exec tracer_log @tid, 'create #rows'
	declare @ids as app_pkids
	declare @processed as app_pkids

	create table #rows(budget_id int primary key)

	if @project_id is not null
		insert into #rows(budget_id)
		select budget_id from budgets
		where project_id = @project_id
			and is_deleted = 0
	else begin
		insert into #rows(budget_id)
		select budget_id from budgets
		where project_id is not null
			and (@budget_id is null or budget_id = @budget_id)
			and (
				not exists(select 1 from @projects)
				or project_id in (select id from @projects)
				)
			and is_deleted = 0
	end

	create table #shares (
		budget_id int, mol_id int, mol_node_id int, task_id int,
		a_read tinyint not null default(1),
		a_update tinyint not null default(0),
		a_access tinyint not null default(0),		
		note varchar(max)
		)
		create index ix_log on #shares(budget_id, mol_id)

	insert into @processed select budget_id from #rows
	
exec tracer_log @tid, 'ОБРАБОТАТЬ ОБЪЕКТЫ БЕЗ НАСЛЕДОВАНИЯ'
	insert into @ids select budget_id from #rows
	exec budgets_calc_access;2 @ids

BEGIN TRY
BEGIN TRANSACTION

exec tracer_log @tid, 'delete from budgets_shares'
	if @budget_id is not null begin
        delete from budgets_shares where budget_id = @budget_id
    end
	delete from budgets_shares where budget_id in (select distinct budget_id from #shares)

exec tracer_log @tid, 'insert into budgets_shares'
	insert into budgets_shares(budget_id, mol_id, a_read, a_update, a_access) 
	select budget_id, mol_id, max(a_read), max(a_update), max(a_access)
	from #shares
	where mol_id is not null
	group by budget_id, mol_id

	exec tracer_close @tid
	if @echo = 1 exec tracer_view @tid

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max) set @err = error_message()
	raiserror (@err, 16, 1)
END CATCH

	drop table #shares
end
GO

create proc budgets_calc_access;2
	@ids app_pkids readonly
as
begin

-- Авторы
	insert into #shares(budget_id, mol_id, a_read, a_update, a_access, note)
	select d.budget_id, d.mol_id, 1, 1, 1, 'Авторы'
	from budgets d
		join @ids x on x.id = d.budget_id

-- Кураторы
	insert into #shares(budget_id, mol_id, a_read, note)
	select d.budget_id, p.curator_id, 1, 'Куратор проекта'
	from budgets d
		join @ids x on x.id = d.budget_id
		join projects p on p.project_id = d.project_id

-- Руководители
	insert into #shares(budget_id, mol_id, a_read, a_update, note)
	select d.budget_id, p.chief_id, 1, 1, 'Руководитель проекта'
	from budgets d
		join @ids x on x.id = d.budget_id
		join projects p on p.project_id = d.project_id

-- Администраторы
	insert into #shares(budget_id, mol_id, a_read, a_update, note)
	select d.budget_id, p.admin_id, 1, 1, 'Администратор проекта'
	from budgets d
		join @ids x on x.id = d.budget_id
		join projects p on p.project_id = d.project_id

-- Доступ в проекте
	declare @sectionBudgets int = (select section_id from projects_sections where ikey = 'budgets')
	insert into #shares(budget_id, mol_id, a_read, a_update, note)
	select d.budget_id, ps.mol_id, ps.a_read, ps.a_update, 'Доступ в проекте'
	from budgets d
		join @ids x on x.id = d.budget_id
		join projects_mols_sections ps on ps.project_id = d.project_id
			and ps.section_id = @sectionBudgets

-- Доступ через подчинённые проекты
	insert into #shares(budget_id, mol_id, a_read, a_update, note)
	select b2.budget_id, ps.mol_id, ps.a_read, ps.a_update, 'Доступ через подчинённые проекты'
	from budgets d
		join @ids x on x.id = d.budget_id
			join projects p on p.project_id = d.project_id
			join projects_mols_sections ps on ps.project_id = d.project_id and ps.section_id = @sectionBudgets
				-- ссылки на дочерние проекты
				join projects_tasks pt on pt.project_id = d.project_id and pt.is_deleted = 0
					-- бюджет подчинённого проекта
					join budgets b2 on b2.project_id = pt.ref_project_id

-- Листы доступа (сотрудники)
	insert into #shares(budget_id, mol_id, a_read, a_update, a_access, note)
	select distinct d.budget_id, meta.mol_id, a_read, a_update, a_access, 'Права доступа (сотрудники)'
	from budgets d
		join @ids x on x.id = d.budget_id
		join budgets_shares_meta meta on meta.budget_id = d.budget_id
	where meta.mol_node_id is null

-- Листы доступа (группы сотрудников)
	insert into #shares(budget_id, mol_id, mol_node_id, a_read, a_update, a_access, note)
	select distinct d.budget_id, m2.mol_id, meta.mol_node_id, 
		a_read, a_update, a_access,
		'Группа сотрудников "' + m.name + '"'
	from budgets d
		join @ids x on x.id = d.budget_id
		join budgets_shares_meta meta on meta.budget_id = d.budget_id
			join projects_mols m on m.id = meta.mol_node_id
				join projects_mols m2 on m2.project_id = m.project_id and m2.node.IsDescendantOf(m.node) = 1
	where meta.mol_node_id is not null
		and m2.mol_id is not null

end
go
