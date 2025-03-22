if object_id('deal_added') is not null drop procedure deal_added
go
create proc deal_added
	@deal_id int
as
begin
	
	set nocount on;

	exec project_apply_template @deal_id
	
	declare @manager_id int = (select manager_id from deals where deal_id = @deal_id)
	exec deal_calc @mol_id = @manager_id, @deal_id = @deal_id

end
go
