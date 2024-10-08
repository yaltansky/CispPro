if object_id('mfr_mstones_calc') is not null drop proc mfr_mstones_calc
go
-- exec mfr_mstones_calc 1000
create proc [mfr_mstones_calc]
	@mol_id int = null,
	@trace bit = 0
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @docs app_pkids;
	insert into @docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id >= 0

	-- @opers
		declare @opers table(
			row_id int identity primary key,
			mfr_doc_id int,
			milestone_id int,
			oper_id int,
			d_fact date,
			fact_q float,
			running_fact_q float,
			index ix (mfr_doc_id, milestone_id, oper_id)
			)

		insert into @opers(mfr_doc_id, milestone_id, oper_id, d_fact, fact_q)
		select o.mfr_doc_id, o.milestone_id, o.oper_id, o.d_to_fact, o.fact_q / c.q_brutto_product
		from sdocs_mfr_opers o
			join @docs i on i.id = o.mfr_doc_id
			join sdocs_mfr_contents c on c.content_id = o.content_id
		where milestone_id is not null
			and d_to_fact is not null
			and fact_q > 0
		order by o.mfr_doc_id, o.milestone_id, o.oper_id, o.d_to_fact

		-- running_q
		update x set running_fact_q = fact_q + isnull(prev_q,0)
		from @opers x
			join (
				select
					row_id,
					prev_q = lag(fact_q, 1, null) over (partition by oper_id order by d_fact)
				from @opers
			) xx on xx.row_id = x.row_id

	-- select top 20 mfr_doc_id, milestone_id, count(*) from @opers 
	-- group by mfr_doc_id, milestone_id 
	-- having count(*) > 20
	-- order by 3

	select * from @opers
	where mfr_doc_id = 732
		and milestone_id = 352	
	order by d_fact

	return

	-- @dates
		declare @dates table(
			mfr_doc_id int,
			milestone_id int,
			d_doc date,
			primary key (mfr_doc_id, milestone_id, d_doc)
			)

		insert into @dates(mfr_doc_id, milestone_id, d_doc)
		select distinct mfr_doc_id, milestone_id, d_fact
		from @opers


end
GO
