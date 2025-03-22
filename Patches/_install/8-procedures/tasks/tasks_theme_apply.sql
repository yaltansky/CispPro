if object_id('tasks_theme_apply') is not null drop proc tasks_theme_apply
go
create proc tasks_theme_apply
	@theme_id int
as
begin
	set nocount on;

    -- apply mols
        delete x from tasks_mols x
            join tasks t on t.task_id = x.task_id
        where t.theme_id = @theme_id
            and x.role_id = 20 and x.mol_id != t.analyzer_id

        delete x from tasks_mols x
            join tasks t on t.task_id = x.task_id
        where t.theme_id = @theme_id
            and x.mol_id not in (t.author_id, t.analyzer_id)
            and x.slice = 'theme'
            and not exists(
                select 1 from tasks_hists where task_id = t.task_id and mol_id = x.mol_id
                )

        insert into tasks_mols(task_id, role_id, mol_id)
        select t.task_id, x.role_id, x.mol_id
        from tasks_themes_mols x
            join tasks t on t.theme_id = x.theme_id
        where x.theme_id = @theme_id
            and not exists(select 1 from tasks_mols where task_id = t.task_id and role_id = x.role_id and mol_id = x.mol_id)

    -- apply sort
        update x set sort_id = xx.sort_id
        from tasks_attrs x
            join tasks_themes_attrs xx on xx.id = x.attr_id
        where xx.theme_id = @theme_id
end
GO
