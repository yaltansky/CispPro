if object_id('projects_autoadmin') is not null drop proc projects_autoadmin
go
create proc projects_autoadmin
as
begin
	set nocount on;

    -- remove missed parent
        update p
        set parent_id = null
        from projects p where type_id = 1 and parent_id is not null
            and not exists(select 1 from projects_tasks where ref_project_id = p.project_id and is_deleted = 0)

end
go
