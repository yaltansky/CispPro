if object_id('mfr_docs_trf_clone') is not null drop proc mfr_docs_trf_clone
go
create proc mfr_docs_trf_clone
	@mol_id int,
	@doc_id int
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET XACT_ABORT ON;

	insert into sdocs(
		subject_id, type_id, status_id,
		d_doc,
		number,
		place_id, place_to_id,
		note,
		add_mol_id,
		add_date
		)
	select 
		subject_id, type_id, status_id,
		d_doc, 
		concat(number, ' (копия)'),
		place_id,
		place_to_id,
		note,
		@mol_id,
		getdate()
	from sdocs
	where doc_id = @doc_id

	declare @new_id int = @@identity

	insert into sdocs_products(
		doc_id,
		mfr_number,
		product_id, unit_id, quantity
		)
	select
		@new_id,
		mfr_number,
		product_id, unit_id, quantity
	from sdocs_products
	where doc_id = @doc_id

	SELECT * FROM V_MFR_SDOCS_TRF WHERE DOC_ID = @NEW_ID
end
go
