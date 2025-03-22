if object_id('budgets_picker') is not null drop proc budgets_picker
go
-- exec budgets_picker 'ЭМ-С20-21%31'
-- exec budgets_picker 'Резерв'
create proc budgets_picker
	@search varchar(max),
	@slice varchar(20) = null
as
begin

    set nocount on;

	set @slice = isnull(@slice, 'all')
	set @search = '%' + replace(@search, ' ', '%') + '%'

	select top 200
		b.BUDGET_ID, NODE_ID = b.BUDGET_ID, b.MAIN_ID, b.NAME
	from budgets b
		left join deals d on d.budget_id = b.budget_id
	where b.status_id <> -1
		and b.main_id is null
		and b.name like @search
		and (
			   (@slice = 'all'
					and d.deal_id is null 
					or (d.deal_id is not null and d.status_id <> 35)
				)
			or (@slice = 'hideDeals' and b.type_id <> 3)
			)
	order by b.name

end
go
