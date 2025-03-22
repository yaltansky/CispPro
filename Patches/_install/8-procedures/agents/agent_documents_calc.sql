if exists(select 1 from sys.objects where name = 'agent_documents_calc')
	drop proc agent_documents_calc
go

create proc agent_documents_calc
	@agent_id int,
	@document_id int = null
as
begin

	set nocount on;

	declare @root hierarchyid = (select top 1 node from documents where key_owner = '/agents/' + cast(@agent_id as varchar));
	
	create table #documents(document_id int primary key, refkey varchar(50))
        create unique index ix_refkey on #documents(refkey)
        
		insert into #documents
		select document_id, refkey from documents where has_childs = 0 and node.IsDescendantOf(@root) = 1
			and (@document_id is null or document_id = @document_id)

	-- documents_mols
	delete from documents_mols where document_id in (select document_id from #documents)

	-- AGENTS_MOLS
	insert into documents_mols(document_id, mol_id)
		select distinct document_id, mol_id
		from (
			select d.document_id, pm.mol_id
			from documents d
				inner join #documents x on x.document_id = d.document_id
				inner join agents_mols pm on pm.agent_id = @agent_id
					inner join mols m on m.mol_id = pm.mol_id
			where (d.account_level_id is null or isnull(pm.account_level_id,0) >= d.account_level_id)

			UNION ALL -- AGENTS: ADMIN_ID
			select d.document_id, pm.mol_id
			from documents d
				inner join #documents x on x.document_id = d.document_id
				inner join (
					select agent_id, admin_id as mol_id from agents where admin_id is not null
				) pm on pm.agent_id = @agent_id
					inner join mols m on m.mol_id = pm.mol_id
			) u

	-- + ROUTES LISTS
	insert into documents_mols(document_id, mol_id)
	select distinct x.document_id, tm.mol_id
	from tasks t
		inner join #documents x on t.refkey = x.refkey
		inner join tasks_mols tm on tm.task_id = t.task_id and tm.role_id = 1
	where not exists(select 1 from documents_mols where document_id = x.document_id and mol_id = tm.mol_id)

end
GO
