if object_id('mfr_reps_docs_trf') is not null drop proc mfr_reps_docs_trf
go
-- exec mfr_reps_docs_trf 1000, 55194
create proc mfr_reps_docs_trf
	@mol_id int,	
	@folder_id int
as
begin

	set nocount on;
	set transaction isolation level read uncommitted;

	create table #docs(id int primary key)
	insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'MFTRF'

	SELECT
		H.DOC_ID,		
		D.DETAIL_ID,
		H.D_DOC,
		H.NUMBER,
		SUBJECT_NAME = S.SHORT_NAME,
		PLACE_NAME = PL.FULL_NAME,
		PLACE_TO_NAME = PL2.FULL_NAME,
		MOL_NAME = M1.NAME,
		EXECUTOR_NAME = M2.NAME,
		AUTHOR_NAME = M3.NAME,
		D.PRODUCT_ID,
		PRODUCT_INNER_NUMBER = P.INNER_NUMBER,
		PRODUCT_NAME = P.NAME,
		PRODUCT_MFR_NUMBER = D.MFR_NUMBER,
		UNIT_NAME = U.NAME,
		D.QUANTITY,
		D.NOTE
  from v_mfr_sdocs_trf h
	join #docs i on i.id = h.doc_id
	join sdocs_products d on d.doc_id = h.doc_id
		left join products p on p.product_id = d.product_id
		left join products_units u on u.unit_id = d.unit_id
	left join mfr_places pl on pl.place_id = h.place_id
	left join mfr_places pl2 on pl2.place_id = h.place_to_id
	left join mols m1 on m1.mol_id = h.mol_id
	left join mols m2 on m2.mol_id = h.mol_to_id
	left join mols m3 on m3.mol_id = h.add_mol_id
	left join subjects s on s.subject_id = h.subject_id

	drop table #docs
end
GO
