if object_id('mfr_milestones_calc') is not null drop proc mfr_milestones_calc
go
/*
declare @docs as app_pkids; insert into @docs select doc_id from mfr_sdocs where plan_status_id = 1
exec mfr_milestones_calc @docs = @docs
*/
create proc mfr_milestones_calc
	@docs app_pkids readonly
as
begin

	set nocount on;

	declare @version_id int = (select max(version_id) from mfr_plans_vers)

    create table #mscalc_docs(id int primary key)
    insert into #mscalc_docs select id from @docs

	update x set 
		ratio_value = x.ratio * sp.value_work
	from sdocs_mfr_milestones x
		join sdocs_products sp on sp.doc_id = x.doc_id and sp.product_id = x.product_id
		join #mscalc_docs i on i.id = x.doc_id

	-- progress d_to ...
	update x set 
		progress = case when o.min_status_id = 100 then 1 else 0 end,
		d_to = o.d_to,
		d_to_plan_auto = o.d_to_plan,
		d_to_predict = o.d_to_predict,
		d_to_fact = case when o.min_status_id = 100 then o.d_to_fact end
	from sdocs_mfr_milestones x
		join #mscalc_docs i on i.id = x.doc_id
		join (
			select 
				mfr_doc_id, product_id, milestone_id,
				d_to = max(d_to),
				d_to_plan = max(d_to_plan),
				d_to_predict = max(d_to_predict),
				d_to_fact = max(d_to_fact),
				min_status_id = min(status_id)
			from sdocs_mfr_opers
			where milestone_id is not null
			group by mfr_doc_id, product_id, milestone_id
		) o on o.mfr_doc_id = x.doc_id and o.product_id = x.product_id and o.milestone_id = x.attr_id

	-- status_id, d_issue
		declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%готовая продукция%')
		update x set 
			status_id = 100,
				-- case
				-- 	when x.status_id < 0 then x.status_id
				-- 	when xx.status_id = 100 then 100
				-- 	else 10
				-- end,
			d_issue = xx.d_to_fact
				-- case
				-- 	when xx.status_id = 100 then xx.d_to_fact
				-- end
		from sdocs x
			join #mscalc_docs i on i.id = x.doc_id
			join (
				select mfr_doc_id, 
					status_id = min(status_id),
					d_to_fact = max(d_to_fact)
				from sdocs_mfr_opers
				where milestone_id = @attr_product
				group by mfr_doc_id
			) xx on xx.mfr_doc_id = x.doc_id
        where x.status_id between 0 and 99
            and xx.status_id = 100

    exec drop_temp_table '#mscalc_docs'
end
GO
