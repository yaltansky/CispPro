if object_id('mfr_plan_qjobs_executors') is not null drop proc mfr_plan_qjobs_executors
go
-- exec mfr_plan_qjobs_executors 1000, 1
create proc mfr_plan_qjobs_executors
	@mol_id int,
	@place_id int = null,
	@wk_sheet_id int = null,
	@sortby varchar(20) = 'name'
as
begin
    set nocount on;

    if @wk_sheet_id is not null set @place_id = null

	create table #result(
		ROW_ID INT IDENTITY,
        MOL_ID INT PRIMARY KEY,
		NAME VARCHAR(100),
		POST_NAME VARCHAR(150),
		PLAN_HOURS FLOAT,
		FACT_HOURS FLOAT,
		LEFT_HOURS FLOAT,
		IS_OVERLOADED BIT,
		SELECTED BIT,
		NOTINLIST BIT,
		IS_WORKING BIT,
        PARENT_ID INT,
        HAS_CHILDS BIT
		)

	-- @mols_selected
		declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mco')
		declare @mols_selected as app_pkids

		if not exists(select 1 from @buffer) and @place_id is not null
		begin
			delete from @buffer;
			insert into @buffer select detail_id from mfr_plans_jobs_queues with(nolock)
			where place_id = @place_id
		end

		insert into @mols_selected
			select distinct mol_id
			from mfr_plans_jobs_executors x with(nolock)
				join @buffer i on i.id = x.detail_id
			where mol_id is not null
		
		if @place_id is not null
			insert into #result(mol_id)
			select mol_id
			from mfr_places_mols
			where place_id = @place_id
        
        else if @wk_sheet_id is not null
        begin
            declare @d_doc date = (select d_doc from mfr_wk_sheets where wk_sheet_id = @wk_sheet_id);
            
            if not exists(select 1 from @buffer)
            begin
                insert into @buffer
                select distinct detail_id
                from mfr_plans_jobs_executors e with(nolock)
                where e.d_doc = @d_doc;
            end

            insert into #result(mol_id, name, parent_id, has_childs, notinlist)
            select mol_id, name, parent_id, has_childs, 0
            from mfr_wk_sheets_details
            where wk_sheet_id = @wk_sheet_id
            order by node
        end

		insert into #result(mol_id, notinlist) 
		select id, 1 from @mols_selected x
		where not exists(select 1 from #result where mol_id = x.id)

	-- set selected
		update x set selected = 1
		from #result x
			join @mols_selected s on s.id = x.mol_id
		
	-- mols
		update x set 
			name = mols.name,
			is_working = mols.is_working
		from #result x
			join mols on mols.mol_id = x.mol_id

	-- plan_hours, fact_hours
		update x set 
			plan_hours = r.plan_hours,
			fact_hours = r.fact_hours,
			is_overloaded = case when r.plan_hours > 60 then 1 end
		from #result x
			join (
				select mol_id, 
					plan_hours = sum(e.plan_duration_wk * dur1.factor / dur_h.factor),
					-- если есть факт, то считаем его равным плану (освоенный план), план - факт равнялся не освоенному плану
					fact_hours = sum(case when e.duration_wk is not null then e.plan_duration_wk end * dur1.factor / dur_h.factor)
				from mfr_plans_jobs_executors e with(nolock)
					join @buffer i on i.id = e.detail_id
					join projects_durations dur1 on dur1.duration_id = e.plan_duration_wk_id
					join projects_durations dur_h on dur_h.duration_id = 2
				where e.d_doc is not null
                group by mol_id
			) r on r.mol_id = x.mol_id

	-- left_hours
		declare @left_hours	float
		update #result set
			@left_hours = isnull(plan_hours,0) - isnull(fact_hours,0),
			left_hours = case when @left_hours > 0 then @left_hours end

	-- select
		if @wk_sheet_id is not null
			select * from #result order by row_id
        else if @sortby = 'name'
			select * from #result order by name
		else if @sortby = 'plan_hours'
			select * from #result order by left_hours desc, name
		else if @sortby = 'status'
			select * from #result order by is_working, name
		else 
			select * from #result order by name

	drop table #result
end
go
