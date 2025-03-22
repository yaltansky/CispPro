if object_id('deals_folder_calctasks') is not null drop proc deals_folder_calctasks
go
-- exec deals_folder_calctasks 700, 12419
create proc deals_folder_calctasks
	@mol_id int,
	@folder_id int
as
begin

	set nocount on;

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

	if exists(
		select 1 from budgets_shares x
			join deals d on d.budget_id = x.budget_id
				join @ids i on i.id = d.deal_id
		where x.mol_id = @mol_id
			and x.a_update = 0
		)
	begin
		raiserror('Среди сделок есть записи, к модерации которых у Вас нет доступа.', 16, 1)
		return
	end

	exec deal_calc_tasks @mol_id = @mol_id, @ids = @ids

end
go
