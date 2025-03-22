if object_id('objs_folders_calc_access') is not null drop proc objs_folders_calc_access
go
create proc objs_folders_calc_access
	@folder_id int = null
as
begin

	set nocount on;
	set ansi_warnings off;
	
	declare @tid int; exec tracer_init 'objs_folders_calc_access', @trace_id = @tid out

	exec tracer_log @tid, 'create #rows'
		declare @ids as app_pkids
		declare @processed as app_pkids

		create table #rows(folder_id int primary key, node hierarchyid, has_childs bit, inherited_access bit)

		if @folder_id is not null
			insert into #rows
			select folder_id, node, has_childs, inherited_access from objs_folders
			where folder_id = @folder_id
		else
			insert into #rows
			select folder_id, node, has_childs, inherited_access from objs_folders
			where is_deleted = 0

		create table #log (
			folder_id int, mol_id int, mol_node_id int, task_id int,
			a_read tinyint not null default(1),
			a_update tinyint not null default(0),
			a_access tinyint not null default(0),		
			note varchar(max)
			)
			create index ix_log on #log(folder_id, mol_id)

		insert into @processed select folder_id from #rows
		
	exec tracer_log @tid, 'ОБРАБОТАТЬ ОБЪЕКТЫ БЕЗ НАСЛЕДОВАНИЯ'
		insert into @ids select folder_id from #rows
		exec objs_folders_calc_access;2 @ids

	exec tracer_log @tid, 'ОБРАБОТАТЬ ОБЪЕКТЫ C НАСЛЕДОВАНИЕМ'
		declare @inherited as app_pkids	
		insert into @inherited select folder_id from #rows where isnull(inherited_access,0) = 1

	exec tracer_log @tid, '    Обработать папки (наследники от @ids)'
		-- #parents от @ids
		create table #parents(folder_id int primary key, node hierarchyid, inherited_access bit)
			insert into #parents
			select distinct d.folder_id, d.node, d.inherited_access
			from objs_folders d 
				join objs_folders d2 on d2.keyword = d.keyword and d2.node.IsDescendantOf(d.node) = 1
					join @inherited x on x.id = d2.folder_id
			where d.has_childs = 1
				and d.folder_id != d2.folder_id

	exec tracer_log @tid, '    Обработать папки без наследования'
		delete from @ids;
		insert into @ids select folder_id from #parents where isnull(inherited_access,0) = 0
		exec objs_folders_calc_access;2 @ids

	exec tracer_log @tid, '    Обработать папки с наследованием'
		delete from @ids;
		insert into @ids select folder_id from #parents where inherited_access = 1
		exec objs_folders_calc_access;3 @ids

	exec tracer_log @tid, '    #children <-- all parents'
		create table #children(folder_id int index ix_folder_id, parent_id int)

		insert into #children(parent_id, folder_id)
		select distinct d2.folder_id, d.folder_id
		from objs_folders d
			join @inherited x on x.id = d.folder_id
			join objs_folders d2 on d2.keyword = d.keyword and d.node.IsDescendantOf(d2.node) = 1
		where (d.is_deleted = 0 and d2.is_deleted = 0)
			and d.folder_id != d2.folder_id

		insert into #log(folder_id, mol_id, mol_node_id, a_read, a_update, a_access, note)
		select c.folder_id, x.mol_id, x.mol_node_id,
			a_read, a_update, a_access,
			concat('Наследование от родителей #', c.parent_id) 
		from objs_folders_shares_meta x
			join #children c on c.parent_id = x.folder_id

	exec tracer_log @tid, '    @folder --> all children'
		delete from #children
		
		insert into #children(parent_id, folder_id)
		select distinct d.folder_id, d2.folder_id
		from objs_folders d
			join @inherited x on x.id = d.folder_id
			join objs_folders d2 on d2.keyword = d.keyword and d2.node.IsDescendantOf(d.node) = 1
		where (d.is_deleted = 0 and d2.is_deleted = 0)
			and d.folder_id != d2.folder_id

		insert into #log(folder_id, mol_id, mol_node_id, a_read, a_update, a_access, note)
		select c.folder_id, x.mol_id, x.mol_node_id,
			a_read, a_update, a_access,
			concat('Наследование от папки #', c.parent_id) 
		from objs_folders_shares_meta x
			join #children c on c.parent_id = x.folder_id

	BEGIN TRY
	BEGIN TRANSACTION

		exec tracer_log @tid, 'delete from objs_folders_shares'
			if @folder_id is not null begin
				delete from objs_folders_shares where folder_id = @folder_id
			end
			delete from objs_folders_shares where folder_id in (select distinct folder_id from #log)

		exec tracer_log @tid, 'insert into objs_folders_shares'
			insert into objs_folders_shares(folder_id, mol_id, a_read, a_update, a_access) 
			select folder_id, mol_id, max(a_read), max(a_update), max(a_access)
			from #log
			where mol_id is not null
			group by folder_id, mol_id

			exec tracer_close @tid

			-- tracing
			if @folder_id is null exec tracer_view @tid

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH

	drop table #log
end
go
create proc objs_folders_calc_access;2
	@ids app_pkids readonly
as
begin

	-- Авторы
		insert into #log(folder_id, mol_id, a_read, a_update, a_access, note)
		select d.folder_id, d.add_mol_id, 1, 1, 1, 'Авторы'
		from objs_folders d
			join @ids x on x.id = d.folder_id

	-- Последние изменения
		insert into #log(folder_id, mol_id, a_read, a_update, a_access, note)
		select d.folder_id, d.update_mol_id, 1, 1, 1, 'Последние изменения'
		from objs_folders d
			join @ids x on x.id = d.folder_id
		where d.update_mol_id is not null

	-- История доступа
		insert into #log(folder_id, mol_id, a_read, a_update, note)
		select distinct d.folder_id, d.add_mol_id, 1, 1, 'История доступа'
		from objs_folders_details d
			join @ids x on x.id = d.folder_id

	-- Листы доступа (сотрудники)
		insert into #log(folder_id, mol_id, a_read, a_update, a_access, note)
		select distinct d.folder_id, meta.mol_id, a_read, a_update, a_access, 'Права доступа (сотрудники)'
		from objs_folders d
			join @ids x on x.id = d.folder_id
			join objs_folders_shares_meta meta on meta.folder_id = d.folder_id
		where meta.mol_node_id is null

	-- Листы доступа (группы сотрудников)
		insert into #log(folder_id, mol_id, mol_node_id, a_read, a_update, a_access, note)
		select distinct d.folder_id, m2.mol_id, meta.mol_node_id, 
			a_read, a_update, a_access,
			'Группа сотрудников "' + m.name + '"'
		from objs_folders d
			join @ids x on x.id = d.folder_id
			join objs_folders_shares_meta meta on meta.folder_id = d.folder_id
				join projects_mols m on m.id = meta.mol_node_id
					join projects_mols m2 on m2.project_id = m.project_id and m2.node.IsDescendantOf(m.node) = 1
		where meta.mol_node_id is not null
			and m2.mol_id is not null

end
go
create proc objs_folders_calc_access;3
	@ids app_pkids readonly
as
begin

	declare @parents table(folder_id int primary key, node hierarchyid, level_id int)
		insert into @parents
		select distinct d.folder_id, d.node, d.node.GetLevel()
		from objs_folders d 
			join objs_folders d2 on 
					d2.keyword = d.keyword
					and d2.node.IsDescendantOf(d.node) = 1
				join @ids x on x.id = d2.folder_id
		where d.has_childs = 1

	declare @level_id int = (select min(level_id) from @parents)
	declare @max_level_id int = (select max(level_id) from @parents)
	declare @while_ids as app_pkids

	while (@level_id <= @max_level_id)
	begin
		delete from @while_ids;
		insert into @while_ids select folder_id from @parents where level_id = @level_id
			and folder_id not in (select folder_id from #log)
	
		if @@rowcount > 0 exec objs_folders_calc_access;2 @while_ids
		set @level_id = @level_id + 1
	end
	
end
go
