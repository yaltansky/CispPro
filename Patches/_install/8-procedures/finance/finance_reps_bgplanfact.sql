if object_id('finance_reps_bgplanfact') is not null drop proc finance_reps_bgplanfact
go
-- exec finance_reps_bgplanfact 700, 8161, 9
create proc finance_reps_bgplanfact
	@mol_id int,
	@folder_id int,
	@principal_id int
as
begin
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    -- access
        declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id

    -- @ids
        if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
        declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'DL'
        declare @bydeals bit = 1

        if not exists(select 1 from @ids) begin
            insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'FD'
            set @bydeals = 0
        end

        create table #resultBgPlanFact(
            budget_id int,
            agent_id int,
            article_id int,
            step_name varchar(100),
            d_doc datetime,
            value_plan decimal(18,2),
            value_fact decimal(18,2),
            --
            index ix_bgplanfact(budget_id, article_id)
            )

        exec finance_reps_bgplanfact;2
            @mol_id = @mol_id,
            @ids = @ids,
            @objects = @objects,
            @bydeals = @bydeals,
            @principal_id = @principal_id

    -- final
        select 
            d.vendor_name,
            direction_name = isnull(d.direction_name,'-'),
            d.mol_name,
            budget_name = b.name,
            article_group_name = a2.name,
            article_name = a.name,
            agent_name = ag.name,
            x.d_doc,
            x.value_plan,
            x.value_fact,
            d.deal_hid,
            budget_hid = concat('#', x.budget_id)
        from #resultBgPlanFact x
            left join budgets b on b.budget_id = x.budget_id
            left join bdr_articles a on a.article_id = x.article_id
                left join bdr_articles a2 on a2.article_id = a.parent_id
            left join v_deals d on d.budget_id = x.budget_id
            left join agents ag on ag.agent_id = x.agent_id

        drop table #resultBgPlanFact
end
go
create proc finance_reps_bgplanfact;2
	@mol_id int,
	@ids app_pkids readonly,
	@objects app_objects readonly,
	@bydeals bit,
	@principal_id int,
	@skip_access bit = 0,
	@skip_fifo bit = 0
as
begin

	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @vendors as app_pkids; insert into @vendors select distinct obj_id from @objects where obj_type = 'vnd'
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit = case when exists(select 1 from @budgets where id = -1) then 1 else 0 end

    -- #buf_budgets
	create table #buf_budgets (budget_id int primary key)

	if @bydeals = 1 begin
		insert into #buf_budgets 
		select distinct d.budget_id
		from deals d
			join @ids i on i.id = d.deal_id			
		where d.budget_id not in (0,33)
			-- access
			and (
				@skip_access = 1
				or d.subject_id in (select id from @subjects)
				or d.vendor_id in (select id from @vendors)
				or (@all_budgets = 1 or d.budget_id in (select id from @budgets))
				)
	end
	
	else begin
		insert into #buf_budgets(budget_id)
		select distinct budget_id
		from findocs# f
		where 
			-- access
			(
				@skip_access = 1
				or f.subject_id in (select id from @subjects)
				or f.subject_id in (select id from @vendors)
				or (@all_budgets = 1 or f.budget_id in (select id from @budgets))
				)
			-- filter
			and findoc_id in (select id from @ids)
			and budget_id not in (0,33)
	end

    -- FIFO (plan/fact)
        if @skip_fifo = 1 goto skip_fifo

        create table #req(
            row_id int identity primary key,
            budget_id int index ix_budget,
            customer_id int,
            d_doc datetime, 		
            step_name varchar(100),
            article_id int,
            value decimal(18,2)
            )

        create table #prv(
            row_id int identity primary key,
            budget_id int index ix_budget,
            customer_id int,
            d_doc datetime, 
            article_id int,
            value decimal(18,2)
            )

        insert into #req(budget_id, customer_id, d_doc, step_name, article_id, value)
        select 
            d.budget_id, d.customer_id, d.d_doc
            , concat(
                row_number() over (partition by d.budget_id order by db.task_date, db.task_name), '-',
                dbo.deal_paystepname(db.task_name, db.date_lag, db.ratio)
                )
            , db.article_id
            , value_bds
        from deals_budgets db
            join deals d on d.deal_id = db.deal_id
                join #buf_budgets bufb on bufb.budget_id = d.budget_id			
        where db.value_bds > 0
        order by d.budget_id, db.task_date, db.task_name
        
        declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')

        insert into #prv(budget_id, customer_id, d_doc, article_id, value)
        select f.budget_id, f.agent_id, f.d_doc, f.article_id, sum(f.value_rur)
        from findocs# f
            join #buf_budgets bufb on bufb.budget_id = f.budget_id				
        where f.value_rur > 0 -- приходы
            and f.account_id not in (select account_id from findocs_accounts where name = @vat_refund)
            and f.subject_id != @principal_id
            and f.agent_id not in (select pred_id from subjects where pred_id is not null)
        group by f.budget_id, f.agent_id, f.d_doc, f.article_id
        order by f.budget_id, f.agent_id, f.d_doc, f.article_id

        declare @fid uniqueidentifier set @fid = newid()

        -- fifo plan/fact
        insert into #resultBgPlanFact(budget_id, agent_id, step_name, d_doc, article_id, value_plan, value_fact)
        select r.budget_id, r.customer_id, r.step_name, r.d_doc, r.article_id, f.value, f.value
        from #req r
            join #prv p on p.budget_id = r.budget_id
            cross apply dbo.fifo(@fid, p.row_id, p.value, r.row_id, r.value) f
        order by r.row_id, p.row_id

        -- unbound plans
        insert into #resultBgPlanFact(budget_id, agent_id, d_doc, step_name, article_id, value_plan)
        select x.budget_id, x.customer_id, x.d_doc, x.step_name, x.article_id, f.value
        from dbo.fifo_left(@fid) f
            join #req x on x.row_id = f.row_id
        where f.value >= 0.01

        -- unbound plans 2
        insert into #resultBgPlanFact(budget_id, agent_id, d_doc, step_name, article_id, value_plan)
        select x.budget_id, x.customer_id, x.d_doc, x.step_name, x.article_id, x.value
        from #req x
        where not exists(select 1 from #prv where budget_id = x.budget_id)

        -- unbound facts
        insert into #resultBgPlanFact(budget_id, d_doc, article_id, value_fact)
        select x.budget_id, x.d_doc, x.article_id, f.value
        from dbo.fifo_right(@fid) f
            join #prv x on x.row_id = f.row_id
        where f.value >= 0.01

        -- unbound facts 2
        insert into #resultBgPlanFact(budget_id, agent_id, d_doc, article_id, value_fact)
        select x.budget_id, x.customer_id, x.d_doc, x.article_id, x.value
        from #prv x
        where not exists(select 1 from #req where budget_id = x.budget_id)

        exec fifo_clear @fid
        skip_fifo:

    -- #resultBgPlanFact
        ;with bg_plan as (
            select d.budget_id, db.article_id, d.customer_id, d.d_doc, sum(value_bds) as value_plan
            from deals_budgets db
                join deals d on d.deal_id = db.deal_id
                    join #buf_budgets bufb on bufb.budget_id = d.budget_id			
            where (@skip_fifo = 1 or db.value_bds < 0)
            group by d.budget_id, db.article_id, d.customer_id, d.d_doc
            )
        , bg_fact as (
            select f.budget_id, f.article_id, f.agent_id, f.d_doc, sum(value_rur) as value_fact
            from findocs# f
                join #buf_budgets bufb on bufb.budget_id = f.budget_id				
            where (
                    (@skip_fifo = 1 and f.value_rur > 0) or
                    -- расходы (в адрес принципала)
                    (f.value_rur < 0 and f.agent_id = (select pred_id from subjects where subject_id = @principal_id))
                )
                and account_id not in (select account_id from findocs_accounts where name = @vat_refund)
            group by f.budget_id, f.article_id, f.agent_id, f.d_doc
            )
        insert into #resultBgPlanFact(budget_id, article_id, agent_id, d_doc, value_plan, value_fact)
        select budget_id, article_id, agent_id, d_doc, sum(value_plan), sum(value_fact) 
        from (
            select budget_id, article_id, agent_id, d_doc, cast(null as decimal(18,2)) as value_plan, value_fact from bg_fact
            union all
            select budget_id, article_id, customer_id, d_doc, value_plan, cast(null as decimal(18,2)) as value_fact from bg_plan
            ) u
        group by budget_id, article_id, agent_id, d_doc

	drop table #buf_budgets
end
go
