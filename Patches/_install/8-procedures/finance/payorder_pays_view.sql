if object_id('payorder_pays_view') is not null drop proc payorder_pays_view
go
-- exec payorder_pays_view 3750
create proc payorder_pays_view
	@payorder_id int,
	@subject_id int = null,
	@d_doc datetime = null,
	@agent_id int = null,
	@search varchar(max) = null,
	@folder_id int = null,
	@findoc_id int = null
as
begin

	set nocount on;	

	declare @status_id int = (select status_id from payorders where payorder_id = @payorder_id)

	-- if @d_doc is null set @d_doc = dbo.today() - 7
	set @d_doc = '2023-01-01'

	create table #ids (findoc_id int index ix_findoc, has_bound bit)

-- добавить ранее привязанные
	insert into #ids(findoc_id, has_bound) select distinct findoc_id, 1
	from payorders_pays x
	where payorder_id = @payorder_id

-- если заявка не оплачена
	if @status_id < 10
	begin
		if @folder_id is not null
			insert into #ids(findoc_id) select obj_id from objs_folders_details x where folder_id = @folder_id and obj_type = 'fd'
				and not exists(select 1 from #ids where findoc_id = x.obj_id)
		
		else begin
			declare @text_search nvarchar(500) = isnull('"' + replace(@search, '"', '*') + '"', '*')
            set @search = '%' + replace(@search, ' ', '%') + '%'

			insert into #ids (findoc_id)
			select top 500 findoc_id
			from findocs x
			where d_doc >= @d_doc				
				and value_ccy < 0 -- расходная часть
				and (@subject_id is null or subject_id = @subject_id)
				and (@agent_id is null or agent_id = @agent_id)
				-- and (@search is null and (
                --     contains(content, @text_search)
                --     or content like @search
                --     ))
				and (@search is null 
                    or content like @search
                    )
				and not exists(select 1 from #ids where findoc_id = x.findoc_id)
			order by d_doc desc
		end
	end

	create table #pays(
		findoc_id int index ix_findoc,
		selected bit,
		other_payorder_id int
		)

	insert into #pays(findoc_id, selected)
	select x.findoc_id, i.has_bound
	from findocs x
		join #ids i on i.findoc_id = x.findoc_id

	-- отметить привязки других заявок
	update x
	set other_payorder_id = pp.payorder_id
	from #pays x
		join payorders_pays pp on pp.findoc_id = x.findoc_id
	where pp.payorder_id <>	 @payorder_id 

-- Выборка
	select p.*, 
		f.d_doc,
		f.number,
		agent_name = ag.name,
		value_pay = f.value_rur,
		f.note
	from #pays p
		join findocs f on f.findoc_id = p.findoc_id
		join agents ag on ag.agent_id = f.agent_id
	order by 
		f.d_doc desc, f.findoc_id
	
	drop table #ids, #pays

end
go
