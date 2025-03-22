if object_id('budget_check_access') is not null drop proc budget_check_access
go
/*
	declare @allowaccess bit
	exec budget_check_access 700, 20, 'update', @allowaccess out
	select @allowaccess
*/
create proc budget_check_access
	@mol_id int,
	@budget_id int,
	@accesstype varchar(16) = 'update', -- read | update
	@allowaccess bit out
as
begin

	set @allowaccess = 0

	-- роли
	if dbo.isinrole(@mol_id, 'Admin,Finance.Budgets.Admin,Finance.Budgets.Operator') = 1
		set @allowaccess = 1
	
	-- владелец
	else if exists(select 1 from budgets where budget_id = @budget_id and @mol_id = mol_id)
		set @allowaccess = 1
				
	-- прописанный доступ
	else begin

		declare @project_id int = (select top 1 project_id from budgets where budget_id = @budget_id)
			
		if @project_id is not null 
			and dbo.isinrole(@mol_id, 'Projects.Admin') = 1
			set @allowaccess = 1
		else if exists(
			select 1 from budgets_shares where budget_id = @budget_id and @mol_id = mol_id 
				and (
					(@accesstype = 'read' and a_read = 1)
					or (@accesstype = 'update' and a_update = 1)
					)
			)
			set @allowaccess = 1
	end

end
GO
