if object_id('payorder_shift') is not null drop proc payorder_shift
go
create proc payorder_shift
	@parent_id int,
	@shift_date datetime,
	@shift_value decimal(18,2)
as
begin

	set nocount on;	
	set xact_abort on;

	declare @value_parent decimal(18,2) = (select value_ccy from payorders where payorder_id = @parent_id)

	if @shift_value > @value_parent
	begin
		raiserror('Сумма переноса превышает сумму заявки, перенос отменён. Измените параметры и повторите операцию.', 16, 1)
		return
	end

BEGIN TRY
BEGIN TRANSACTION

	declare @count_childs int = isnull((select count(*) from payorders where parent_id = @parent_id and status_id not in (-2,-1)), 0)

	-- purge deleted details
	delete from payorders_details
	where payorder_id = @parent_id
		and is_deleted = 1
	
	-- new order
	insert into payorders(
		dbname, type_id, parent_id, subject_id, status_id, mol_id, number, agent_id, recipient_id, d_pay_plan, ccy_id, value_ccy, pays_path, note
		)
	select
		db_name(), type_id, @parent_id, subject_id, status_id, mol_id, 
		substring(concat(number, '/', @count_childs + 1), 1, 50),
		agent_id, recipient_id, @shift_date, ccy_id, @shift_value, pays_path, note
	from payorders
	where payorder_id = @parent_id

	declare @child_id int = @@identity
	declare @ratio float = @shift_value / @value_parent

	-- new order details
	insert into payorders_details(
		payorder_id, budget_id, article_id, value_ccy, note
		)
	select
		@child_id, budget_id, article_id, value_ccy * @ratio, note
	from payorders_details
	where payorder_id = @parent_id

	-- exec payorder_move @child_id, @parent_id
	-- has_childs of parent
	update x set 
		has_childs = case when exists(select 1 from payorders_childs where parent_id = x.payorder_id) then 1 else 0 end
	from payorders x
	where x.payorder_id = @parent_id
	
	-- decrease
	update payorders_details
	set value_ccy = (1 - @ratio) * value_ccy
	where payorder_id = @parent_id

	-- ошибки округления
	declare @value_parent_new decimal(18,2) = (select value_ccy from payorders where payorder_id = @parent_id)
	declare @value_child decimal(18,2) = (select value_ccy from payorders where payorder_id = @child_id)
	declare @value_diff decimal(18,2) = @value_parent - (@value_parent_new + @value_child)

	if abs(@value_diff) > 0.00
	begin
		declare @detail_id int = (select max(id) from payorders_details where payorder_id = @child_id)
		update payorders_details set value_ccy = value_ccy + @value_diff where id = @detail_id
	end

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max) = error_message()
	raiserror (@err, 16, 1)
END CATCH

	return @child_id

end
go
