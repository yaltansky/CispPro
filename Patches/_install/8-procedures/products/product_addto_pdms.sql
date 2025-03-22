if object_id('product_addto_pdms') is not null drop proc product_addto_pdms
go
create proc product_addto_pdms
	@mol_id int,
	@item_id int,
	@pdm_id int out
as
begin

	set nocount on;

    if exists(select 1 from mfr_pdms where item_id = @item_id)
    begin
        set @pdm_id = null
        return
    end

	insert into mfr_pdms(
		item_id, status_id, is_default, add_mol_id, add_date
		)
	values
	 	(@item_id, 0, 1, @mol_id, getdate())
		
	set @pdm_id = (select pdm_id from mfr_pdms where item_id = @item_id)

end
go
