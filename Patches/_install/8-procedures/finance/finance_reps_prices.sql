if object_id('finance_reps_prices') is not null drop proc finance_reps_prices
go
-- exec finance_reps_prices 1000, -1
create proc finance_reps_prices
	@mol_id int,
	@folder_id int,
	@attr_id int = null -- характеристика для группы
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- folder
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		
		declare @docs as app_pkids
		insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'INV'

	-- access
		declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
		declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'SBJ'

	-- select
		select
			AgentName = a.name,
			DocId = sd.doc_id,
			DocDate = sd.d_doc,
			DocNumber = sd.number,
			ProductGroup = pa.attr_value,
			ProductName = p.name,
			Quantity = sp.quantity,
			ValuePure = sp.value_pure,
			PricePure = sp.price_pure,
			UnitName = u.name
		from sdocs sd
			join sdocs_products sp on sp.doc_id = sd.doc_id
			join agents a on a.agent_id = sd.agent_id
			join products p on p.product_id = sp.product_id
			join products_units u on u.unit_id = sp.unit_id
			left join products_attrs pa on pa.product_id = sp.product_id and pa.attr_id = @attr_id
			join @docs i on i.id = sd.doc_id

end
go