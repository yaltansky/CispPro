if object_id('sdoc_calc_access') is not null drop proc sdoc_calc_access
go
create proc sdoc_calc_access
	@doc_id int
as
begin
	set nocount on;

	declare @uids app_pkids
    insert into @uids select obj_uid from objs where owner_type in ('sd', 'mfr') and owner_id = @doc_id

	delete from objs_shares where obj_uid in (select id from @uids) and add_mol_id = 0 -- слой авто-обновления

	insert into objs_shares(
        obj_uid, mol_id, a_read, a_update, a_access, add_mol_id, reserved
        )
	select u.id, mols.mol_id, 1, 0, 1, 0, 'auto'
	from @uids u,
        (
		select m.manager_id, d.chief_id
		from (
			select manager_id from deals where deal_id in (select deal_id from sdocs where doc_id = @doc_id)
			) m
			left join mols_employees me on me.mol_id = m.manager_id and me.date_fire is null
				left join depts d on d.dept_id = me.dept_id
		) mm
		join mols on mols.mol_id in (mm.manager_id, isnull(mm.chief_id,0))
	where not exists(select 1 from objs_shares where obj_uid = u.id and mol_id = mols.mol_id)

	delete from sdocs_mols where doc_id = @doc_id

	insert into sdocs_mols(doc_id, mol_id, a_read, a_update, a_access)
	select @doc_id, mol_id, a_read, a_update, a_access
	from objs_shares
	where obj_uid in (select id from @uids)

end
go
