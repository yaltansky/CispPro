if object_id('project_mols_calc') is not null drop proc project_mols_calc
GO
create proc project_mols_calc
	@project_id int = null,
	@projects app_pkids readonly,
	@level int = null,
	@echo bit = 0
as
begin

	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	if @level > 1
	begin
		raiserror('project_mols_calc: превышен уровень рекурсивного вызова процедуры.', 16, 1)
		return
	end

    -- hierarchyid
        if @project_id is not null
        begin
            update x
            set x.mol_id = m.mol_id
            from projects_mols x
                join mols m on m.name = x.name
            where x.project_id = @project_id
                and x.mol_id is null

            update x
            set name = m.name,
                post_name = m.posts_names
            from projects_mols x
                join mols m on m.mol_id = x.mol_id
            where x.project_id = @project_id

            update projects_mols set node = null where project_id = @project_id

            declare @where_rows varchar(100) = 'project_id = ' + cast(@project_id as varchar)
            exec tree_calc_nodes 'projects_mols', 'id', @where_rows = @where_rows, @sortable = 0
        end

    -- access
        create table #projects(project_id int primary key)
        if @project_id is not null
            insert into #projects select @project_id
        else if exists(select 1 from @projects)
            insert into #projects select id from @projects
        else
            insert into #projects select project_id from projects where type_id not in (3) and status_id >= 0

        create table #access (project_id int, mol_id int, node hierarchyid, inherited_access bit, section_id int, a_read tinyint, a_update tinyint)
        create table #result (project_id int, mol_id int, section_id int, a_read tinyint, a_update tinyint)

    -- get all childs
        insert into #access(project_id, mol_id, node, inherited_access, section_id, a_read, a_update)
            select m.project_id, m.mol_id, m.node, m.inherited_access, s.section_id, s.is_required, 0
            from projects_mols m, projects_sections s
            where m.project_id in (select project_id from #projects)
                and m.has_childs = 0
                and m.mol_id is not null

    -- get self
        insert into #access(project_id, mol_id, node, inherited_access, section_id, a_read, a_update)
            select m.project_id, m.mol_id, m.node, m.inherited_access, s.section_id, s.a_read, s.a_update
            from projects_mols m
                join projects_mols_sections_meta s on s.project_id = m.project_id and s.tree_id = m.id
            where m.project_id in (select project_id from #projects)
                and m.has_childs = 0
                and m.mol_id is not null

    -- + inherits from parents
        insert into #access(project_id, mol_id, section_id, a_read, a_update)
            select m.project_id, a.mol_id, s.section_id, s.a_read, s.a_update
            from #access a
                join projects_mols m on m.project_id = a.project_id and a.node.IsDescendantOf(m.node) = 1
                join projects_mols_sections_meta s on s.project_id = m.project_id and s.tree_id = m.id			
            where m.project_id in (select project_id from #projects)
                and a.inherited_access = 1

    -- curator_id
        insert into #access(project_id, mol_id, section_id, a_read, a_update)
        select p.project_id, p.curator_id, s.section_id, 1, 0
        from projects p
            join #projects x on x.project_id = p.project_id
            cross apply projects_sections s

    -- chief_id, admin_id
        insert into #access(project_id, mol_id, section_id, a_read, a_update)
        select p.project_id, p.mol_id, s.section_id, 1, 1
        from #projects x 
            join (
                select distinct project_id, mol_id
                from (
                    select project_id, chief_id as mol_id from projects
                    union select project_id, admin_id from projects
                    ) u
            ) p on p.project_id = x.project_id
            cross apply projects_sections s

        declare @sectionBudgets int = (select section_id from projects_sections where ikey = 'budgets')

    -- result access
        insert into #result(project_id, mol_id, section_id, a_read, a_update)
        select 
            a.project_id, a.mol_id, a.section_id,
            max(a.a_read) as a_read,
            max(a.a_update) as a_update
        from #access a
            join projects p on p.project_id = a.project_id
        where p.type_id <> 3
            or a.section_id = @sectionBudgets
        group by a.project_id, a.mol_id, a.section_id

    BEGIN TRY
    BEGIN TRANSACTION
        
        delete from projects_mols_sections 
        where project_id in (select project_id from #projects)

        insert into projects_mols_sections(project_id, mol_id, section_id, a_read, a_update)
        select project_id, mol_id, section_id, a_read, a_update
        from #result
        where a_read + a_update > 0

    -- + наследование прав от Программы к подчинённым проектам
        if @project_id is not null
        begin
            declare @ref_projects app_pkids
                insert into @ref_projects
                select distinct ref_project_id
                from projects_tasks where project_id = @project_id and ref_project_id is not null

            if exists(select 1 from @ref_projects)
            begin
                declare @meta table(project_id int, tree_id int, section_id int, a_read tinyint, a_update tinyint)

                delete x 
                    output deleted.project_id, deleted.tree_id, deleted.section_id, deleted.a_read, deleted.a_update into @meta
                from projects_mols_sections_meta x			
                    join @ref_projects ref on ref.id = x.project_id
                
                insert into @meta(project_id, tree_id, section_id, a_read, a_update)
                select ref.id, pmols2.id, meta.section_id, meta.a_read, meta.a_update
                from projects_mols_sections_meta meta
                    join projects_mols pmols on pmols.project_id = meta.project_id and pmols.id = meta.tree_id and pmols.mol_id is not null
                    cross join @ref_projects ref
                    join projects_mols pmols2 on pmols2.project_id = ref.id and pmols2.mol_id = pmols.mol_id
                where meta.project_id = @project_id

                insert into projects_mols_sections_meta(project_id, tree_id, section_id, a_read, a_update)
                select project_id, tree_id, section_id, max(a_read), max(a_update)
                from @meta
                group by project_id, tree_id, section_id

                set @level = isnull(@level,0) + 1
                exec project_mols_calc @projects = @ref_projects, @level = @level
            end
        end -- наследование от Программы

    COMMIT TRANSACTION
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        declare @err varchar(max); set @err = error_message()
        raiserror (@err, 16, 3)
    END CATCH

	declare @processed as app_pkids; insert into @processed select project_id from #projects
	exec budgets_calc_access @projects = @processed, @echo = @echo

	exec drop_temp_table '#projects,#access,#result'
end
GO
