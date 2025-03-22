if object_id('documents_calc_access') is not null drop proc documents_calc_access
go
create proc documents_calc_access
	@document_id int = null,
	@project_id int = null,
	@trace bit = 0
as
begin
	set nocount on;
	
	if @project_id is null and @document_id is not null
	begin
		declare @owner_id int, @owner_key varchar(32)
		exec document_get_owner @document_id, @owner_id out, @owner_key out
		if @owner_key like '%projects%' set @project_id = @owner_id
	end

	declare @tid int; exec tracer_init 'documents_calc_access', @trace_id = @tid out

    -- @root_id
        declare @root_id int, @root hierarchyid
        if @project_id is not null
            select
                @root_id = document_id,
                @root = node
            from documents where key_owner = '/projects/' + cast(@project_id as varchar)
        else
            select
                @root_id = document_id,
                @root = node
            from documents where name = 'Общие Документы' and parent_id is null
		
	declare @tid_note varchar(100) = 'calc documents from @root ' + cast(@root_id as varchar)

    exec tracer_log @tid, @tid_note
        
        if @document_id is null
            exec documents_calc @root_id = @root_id
    exec tracer_log @tid, 'create #documents'
        declare @processed as app_pkids
        declare @ids as app_pkids

        create table #documents(document_id int primary key, node hierarchyid, has_childs bit, inherited_access bit)
            insert into #documents
            select document_id, node, has_childs, inherited_access from documents
            where (@document_id is null and node.IsDescendantOf(@root) = 1)
                or document_id = @document_id

        create table #log (
            document_id int, mol_id int, mol_node_id int, doc_node_id int, task_id int,
            a_read tinyint not null default(1),
            a_update tinyint not null default(0),
            a_access tinyint not null default(0),		
            note varchar(max)
            )
            create index ix_log on #log(document_id, mol_id)

        insert into @processed select document_id from #documents
    exec tracer_log @tid, 'ОБРАБОТАТЬ ОБЪЕКТЫ БЕЗ НАСЛЕДОВАНИЯ'
        insert into @ids select document_id from #documents
        exec documents_calc_access;2 @project_id, @ids
    exec tracer_log @tid, 'ОБРАБОТАТЬ ОБЪЕКТЫ C НАСЛЕДОВАНИЕМ'
        declare @inherited as app_pkids
        
        delete from @inherited;
        insert into @inherited select document_id from #documents where isnull(inherited_access,0) = 1
    exec tracer_log @tid, '    Обработать папки (наследники от @ids)'
        -- #parents от @ids
        create table #parents(document_id int primary key, node hierarchyid, inherited_access bit)
            insert into #parents
            select distinct d.document_id, d.node, d.inherited_access
            from documents d 
                join documents d2 on d2.node.IsDescendantOf(d.node) = 1
                    join @inherited x on x.id = d2.document_id
            where d.node.IsDescendantOf(@root) = 1 
                and d.has_childs = 1
                and d.node <> @root
    exec tracer_log @tid, '    Обработать папки без наследования'
        delete from @ids;
        insert into @ids select document_id from #parents where isnull(inherited_access,0) = 0
        exec documents_calc_access;2 @project_id, @ids
    exec tracer_log @tid, '    Обработать папки с наследованием'
        delete from @ids;
        insert into @ids select document_id from #parents where inherited_access = 1
        exec documents_calc_access;3 @project_id, @root_id, @ids
    exec tracer_log @tid, '    Наследовать доступ от папок'
        create table #children(document_id int, parent_id int)

            insert into #children
            select d.document_id, d2.document_id
            from documents d
                join @inherited x on x.id = d.document_id
                join documents d2 on d2.node.IsDescendantOf(@root) = 1 
                    and d.node.IsDescendantOf(d2.node) = 1
                    and d2.document_id <> @root_id
                    and d.document_id <> d2.document_id
    exec tracer_log @tid, '    Доступ сотрудникам'
        insert into #log(
            document_id, mol_id, mol_node_id, doc_node_id, 
            a_read, a_update, a_access,
            note)
        select 
            c.document_id, x.mol_id, x.mol_node_id, c.parent_id, 
            a_read, a_update, a_access,
            'Наследование от папки #' + cast(c.parent_id as varchar) 
            + case when x.note is null then '' else ', ' + x.note end
        from #log x
            join #children c on c.parent_id = x.document_id

    BEGIN TRY
    BEGIN TRANSACTION
        exec tracer_log @tid, 'delete from documents_mols'
            if @document_id is not null begin
                delete from documents_mols where document_id = @document_id
            end
            delete from documents_mols where document_id in (select distinct document_id from #log)
        exec tracer_log @tid, 'insert into documents_mols'
            insert into documents_mols(document_id, mol_id, a_read, a_update, a_access) 
            select document_id, mol_id, max(a_read), max(a_update), max(a_access)
            from #log
            where mol_id is not null
            group by document_id, mol_id

            exec tracer_close @tid
    COMMIT TRANSACTION
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        declare @err varchar(max) set @err = error_message()
        raiserror (@err, 16, 1)
    END CATCH

	-- tracing
	if @trace = 1 begin
		-- exec tracer_view @tid
		select mols.name, * from #log x, mols where x.mol_id = mols.mol_id order by mols.name
	end

	if object_id('#log') is not null drop table #log
end
GO
create proc documents_calc_access;2
	@project_id int,
	@ids app_pkids readonly
as
begin
    if @project_id is not null
    begin
    -- Полный доступ для: Куратора, Руководителя, Администратора
        insert into #log(document_id, mol_id, a_read, note)
        select d.document_id, p.curator_id, 1, 'Куратор проекта'
        from documents d
            join @ids x on x.id = d.document_id
            join projects p on p.project_id = @project_id

        insert into #log(document_id, mol_id, a_read, a_update, note)
        select d.document_id, p.chief_id, 1, 1, 'Руководитель проекта'
        from documents d
            join @ids x on x.id = d.document_id
            join projects p on p.project_id = @project_id

        insert into #log(document_id, mol_id, a_read, a_update, note)
        select d.document_id, p.admin_id, 1, 1, 'Администратор проекта'
        from documents d
            join @ids x on x.id = d.document_id
            join projects p on p.project_id = @project_id
    -- Модераторы документов
        insert into #log(document_id, mol_id, a_read, a_update, note)
        select d.document_id, s.mol_id, s.a_read, s.a_update, 'Модератор документов'
        from documents d
            join @ids x on x.id = d.document_id
            join projects_mols_sections s on s.project_id = @project_id 
                and s.section_id = (select section_id from projects_sections where ikey = 'docs')			
        where isnull(d.account_level_id,0) = 0 -- кроме ДСП
    -- Уровни доступа (ДСП)
        insert into #log(document_id, mol_id, a_read, note)
        select distinct d.document_id, pm.mol_id, 1, 'Уровни доступа (ДСП,КТ)'
        from documents d
            join @ids x on x.id = d.document_id
            join projects_mols pm on pm.project_id = @project_id
        where pm.account_level_id >= d.account_level_id
            and d.account_level_id > 0
    end

    -- Листы согласования, публикации, задачи, поручения
        declare @tasks table(task_id int, document_id int)
        insert into @tasks 
            select task_id, d.document_id
            from tasks t
                join documents d on t.refkey = d.refkey
                    join @ids x on x.id = d.document_id
        where isnull(d.account_level_id,0) = 0 -- кроме ДСП
            and t.status_id not in (-1)

        -- координаторы задач
        insert into #log(document_id, mol_id, a_read, note)
        select distinct x.document_id, t.analyzer_id, 1, 'Листы согласования, публикации, задачи, поручения'
        from tasks t		
            join @tasks x on x.task_id = t.task_id

        -- участники задач
        insert into #log(document_id, mol_id, a_read, note)
        select distinct x.document_id, tm.mol_id, 1, 'Листы согласования, публикации, задачи, поручения'
        from tasks t		
            join @tasks x on x.task_id = t.task_id
            join tasks_mols tm on tm.task_id = t.task_id
    -- Листы доступа (сотрудники)
        insert into #log(document_id, mol_id, a_read, a_update, a_access, note)
        select distinct d.document_id, meta.mol_id, a_read, a_update, a_access, 'Права доступа (сотрудники)'
        from documents d
            join @ids x on x.id = d.document_id
            join documents_mols_meta meta on meta.document_id = d.document_id
        where meta.mol_node_id is null
            and isnull(d.account_level_id,0) = 0 -- кроме ДСП
    -- Листы доступа (группы сотрудников)
        insert into #log(document_id, mol_id, mol_node_id, a_read, a_update, a_access, note)
        select distinct d.document_id, m2.mol_id, meta.mol_node_id, 
            a_read, a_update, a_access,
            'Группа сотрудников "' + m.name + '"'
        from documents d
            join @ids x on x.id = d.document_id
            join documents_mols_meta meta on meta.document_id = d.document_id
                join projects_mols m on m.id = meta.mol_node_id
                    join projects_mols m2 on m2.project_id = m.project_id and m2.node.IsDescendantOf(m.node) = 1
        where meta.mol_node_id is not null
            and m2.mol_id is not null
            and isnull(d.account_level_id,0) = 0 -- кроме ДСП
end
go
create proc documents_calc_access;3
	@project_id int,
	@root_id int,
	@ids app_pkids readonly
as
begin
	declare @root hierarchyid = (select node from documents where document_id = @root_id)

	declare @parents table(document_id int primary key, node hierarchyid, level_id int)
		insert into @parents
		select distinct d.document_id, d.node, d.node.GetLevel()
		from documents d 
			join documents d2 on d2.node.IsDescendantOf(d.node) = 1
				join @ids x on x.id = d2.document_id
		where d.node.IsDescendantOf(@root) = 1 
			and d.has_childs = 1
			and d.document_id <> @root_id

	declare @level_id int = (select min(level_id) from @parents)
	declare @max_level_id int = (select max(level_id) from @parents)
	declare @while_ids as app_pkids

	while (@level_id <= @max_level_id)
	begin
		delete from @while_ids;
		insert into @while_ids select document_id from @parents where level_id = @level_id
			and document_id not in (select document_id from #log)
		exec documents_calc_access;2 @project_id, @while_ids
		set @level_id = @level_id + 1
	end
end
go
