if object_id('sdoc_clone') is not null drop procedure sdoc_clone
go
create proc sdoc_clone	
	@mol_id int,
	@doc_id int
as
begin

	set nocount on;

	declare @docs app_pkids
	insert into @docs select @doc_id
	
	declare @map app_mapids

	insert into sdocs(
		parent_id, number, status_id, add_mol_id, add_date,
		type_id, subject_id, d_doc, d_delivery, d_issue, deal_id, deal_number, agent_id, agent_dogovor, stock_id, mol_id, ccy_id, ccy_rate, value_ccy, value_rur,
		note, refkey, d_delivery_plan, plan_id, d_issue_plan, d_issue_calc, d_issue_forecast, d_calc_contents, d_calc_links, project_id, d_calc_jobs, d_calc_jobs_buys,
		project_task_id, replicate_date, source_id, template_id, template_name, template_note, dogovor_number, dogovor_date, spec_number, spec_date, budget_id, pay_conditions, priority_id,
		d_ship, place_id, place_to_id, executor_id, priority_final, priority_sort, mol_to_id, d_doc_ext
		)
		output inserted.parent_id, inserted.doc_id into @map
	select 
		x.doc_id, concat('копия ', x.number), 0 /* черновик */, @mol_id, getdate(), 
		x.type_id, x.subject_id, x.d_doc, x.d_delivery, x.d_issue, x.deal_id, x.deal_number, x.agent_id, x.agent_dogovor, x.stock_id, x.mol_id, x.ccy_id, x.ccy_rate, x.value_ccy, x.value_rur, x.note, x.refkey, 
		x.d_delivery_plan, x.plan_id, x.d_issue_plan, x.d_issue_calc, x.d_issue_forecast, x.d_calc_contents, x.d_calc_links, x.project_id, x.d_calc_jobs, x.d_calc_jobs_buys, x.project_task_id, x.replicate_date, x.source_id, x.template_id, x.template_name, x.template_note, x.dogovor_number, x.dogovor_date, x.spec_number, x.spec_date, x.budget_id, x.pay_conditions, x.priority_id, x.d_ship, x.place_id, x.place_to_id, x.executor_id, x.priority_final, x.priority_sort, x.mol_to_id, x.d_doc_ext
	from sdocs x
		join @docs i on i.id = x.doc_id
	
	insert into sdocs_products(doc_id, product_id, quantity, w_netto, w_brutto, unit_id, price, price_pure, price_pure_trf, nds_ratio, value_pure, value_nds, value_ccy, value_rur, note, refkey, value_work, price_list, mfr_number, dest_product_id, plan_q, due_date, dest_unit_id, dest_quantity, mfr_number_from, draft_id)
	select map.new_id, x.product_id, x.quantity, x.w_netto, x.w_brutto, x.unit_id, x.price, x.price_pure, x.price_pure_trf, x.nds_ratio, x.value_pure, x.value_nds, x.value_ccy, x.value_rur, x.note, x.refkey, x.value_work, x.price_list, x.mfr_number, x.dest_product_id, x.plan_q, x.due_date, x.dest_unit_id, x.dest_quantity, x.mfr_number_from, x.draft_id
	from sdocs_products x
		join @map map on map.id = x.doc_id
	order by x.doc_id, x.detail_id

	select * from sdocs where doc_id in (select new_id from @map)
end
go
