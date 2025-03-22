if object_id('objs_folder_check_access') is not null drop proc objs_folder_check_access
go
/*
	declare @allowaccess bit
	exec objs_folder_check_access 700, 20, 'update', @allowaccess out
	select @allowaccess
*/
create proc objs_folder_check_access
	@mol_id int,
	@folder_id int,
	@accesstype varchar(16) = 'update', -- read | update
	@allowaccess bit out
as
begin

	set @allowaccess = 0

	-- роли
	if dbo.isinrole(@mol_id, 'Admin') = 1
		set @allowaccess = 1
	
	-- владелец
	else if exists(select 1 from objs_folders where folder_id = @folder_id and @mol_id = add_mol_id)
		set @allowaccess = 1
				
	-- прописанный доступ
	else if exists(
		select 1 from objs_folders_shares where folder_id = @folder_id and @mol_id = mol_id 
			and (
				(@accesstype = 'read' and a_read = 1)
				or (@accesstype = 'update' and a_update = 1)
				)
		)
		set @allowaccess = 1

end
GO
