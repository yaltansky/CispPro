if object_id('payorder_merge') is not null drop proc payorder_merge
go
create proc payorder_merge
	@mol_id int,
	@primary_order_id int
as
begin

	set nocount on;	
	set xact_abort on;

	declare @folder_id int = dbo.objs_buffer_id(@mol_id)
	
	declare @ids as app_pkids	
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'PO'

	if not exists(select 1 from @ids where id = @primary_order_id)
	begin
		raiserror('Среди заявок в буфере не найдена главная заявка (%d), которую Вы указали.', 16, 1, @primary_order_id)
		return
	end

	declare @orders table(parent_id int, payorder_id int primary key, subject_id int, recipient_id int)
		insert into @orders(parent_id, payorder_id, subject_id, recipient_id)
		select x.parent_id, x.payorder_id, x.subject_id, x.recipient_id
		from payorders x
			join @ids i on i.id = x.payorder_id

	if (select count(distinct subject_id) from @orders) > 1
	begin
		raiserror('Заявки в буфере должны быть с одним субъектом учёта.', 16, 1)
		return
	end

	if (select count(distinct recipient_id) from @orders) > 1
	begin
		raiserror('Заявки в буфере должны быть с одним получателем.', 16, 1)
		return
	end

	declare @orders_details table(budget_id int, article_id int, value_ccy decimal(18,2))
		insert into @orders_details(budget_id, article_id, value_ccy)
		select budget_id, article_id, sum(value_ccy)
		from payorders_details x
			join @ids i on i.id = x.payorder_id
		group by budget_id, article_id

	-- change primary order
	delete from payorders_details where payorder_id = @primary_order_id

	insert into payorders_details(payorder_id, budget_id, article_id, value_ccy)
	select @primary_order_id, budget_id, article_id, value_ccy
	from @orders_details

	-- childs numbers -> paret
	declare @numbers varchar(max)
	update x
	set @numbers = (
		select cast(p.number as varchar(max)) + ', ' as [text()]
		from (
			select distinct number
			from payorders
				join @ids i on i.id = payorders.payorder_id
			where isnull(number,'') <> ''
				and payorder_id <> x.payorder_id
			) p
		for xml path('')
		),
		note = concat(x.note, ', дочерние: ', @numbers)
	from payorders x
	where x.payorder_id = @primary_order_id

	-- archive childs
	update x set 
		status_id = -2,
		parent_id = @primary_order_id
	from payorders x
		join @ids i on i.id = x.payorder_id
	where x.payorder_id <> @primary_order_id

	-- has_childs of parent
	update x set 
		has_childs = case when exists(select 1 from payorders_childs where parent_id = x.payorder_id) then 1 else 0 end
	from payorders x
	where x.payorder_id = @primary_order_id

end
go
