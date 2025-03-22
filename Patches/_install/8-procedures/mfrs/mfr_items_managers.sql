if object_id('mfr_items_managers') is not null drop proc mfr_items_managers
go
-- exec mfr_items_managers @plan_id = 0
create proc mfr_items_managers
	@plan_id int = null,
	@doc_id int = null
as
begin

    set nocount on;

	declare @attr_manager int = (select top 1 attr_id from prodmeta_attrs where name = 'закупка.КодМенеджера')

	select * from mols
	where exists(
		select 1 
		from products_attrs pa
			join sdocs_mfr_contents c on c.item_id = pa.product_id and c.is_deleted = 0			
				join sdocs sd on sd.doc_id = c.mfr_doc_id
					join mfr_plans pl on pl.plan_id = sd.plan_id and pl.status_id = 1
		where pa.attr_id = @attr_manager	
			and (nullif(@plan_id,0) is null or sd.plan_id = @plan_id)
			and (nullif(@doc_id,0) is null or sd.doc_id = @doc_id)
			and pa.attr_value_id = mols.mol_id
		)
	order by name
end
go
