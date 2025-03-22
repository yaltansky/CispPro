if object_id('mfr_plan_change_orders') is not null drop proc mfr_plan_change_orders
go
-- exec mfr_plan_change_orders 1, 'view'
create proc mfr_plan_change_orders
	@mol_id int,
	@plan_id int,	
	@action varchar(16)
as
begin

    set nocount on;

	if @action = 'add' 
	begin
		declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfr')

		update x set plan_id = @plan_id
		from sdocs x
			join @buffer i on i.id = x.doc_id

		exec sys_set_triggers 0
			update x set plan_id = @plan_id
			from sdocs_mfr_contents x
				join @buffer i on i.id = x.mfr_doc_id
		exec sys_set_triggers 1
	end

end
go
