if object_id('mfr_items_view_gantt') is not null drop proc mfr_items_view_gantt
go
-- exec mfr_items_view_gantt 651733, 26061 -- CЭЗ
create proc mfr_items_view_gantt
	@doc_id int,
	@product_id int,
	@view_id int = null -- 10 - XML
as
begin
	set nocount on;

    declare @attr_gantt int =  (select attr_id from prodmeta_attrs where code = 'NodeGantt');

    create table #gantt(content_id int index ix_content, node hierarchyid);
        insert into #gantt(content_id, node)
        select c.content_id, c.node
        from sdocs_mfr_contents c
            join sdocs_mfr_contents_attrs ca on ca.content_id = c.content_id
        where c.mfr_doc_id = @doc_id
            and c.product_id = @product_id
            and ca.attr_id = @attr_gantt;

    insert into #gantt(content_id, node)
    select c.content_id, c.node
    from sdocs_mfr_contents c
        join #gantt g on g.node.IsDescendantOf(c.node) = 1
    where c.mfr_doc_id = @doc_id
        and c.product_id = @product_id;

    select 
        c.node,
        c.content_id,
        c.parent_id,
        c.child_id,
        c.has_childs,
        c.item_id,
        c.name,
        (case @view_id
				when 1 then c.opers_from
				when 20 then c.opers_from_plan
				when 40 then c.opers_from_predict
                else c.opers_from
			end) as d_from,
        (case @view_id
				when 1 then c.opers_to
				when 20 then c.opers_to_plan
				when 40 then c.opers_to_predict
                else c.opers_to
            end) as d_to,
        (case @view_id
				when 1 then c.duration_buffer
				when 20 then c.duration_buffer_ploper
				when 40 then c.duration_buffer_predict
                else c.duration_buffer
			end) as duration_buffer,
        (
            select 
                sum(case when o.status_id = 100 then o.duration_wk end) -- сделанные операции
                / sum(nullif(o.duration_wk, 0)) -- все операции
            from (
                select cc.content_id
                from sdocs_mfr_contents cs
                    join sdocs_mfr_contents cc on cc.mfr_doc_id = cs.mfr_doc_id
                        and cc.product_id = cs.product_id
                        and cc.node.IsDescendantOf(cs.node) = 1
                        and cc.is_buy = 0
                where cs.content_id = c.content_id
                ) cc
                join sdocs_mfr_opers o on o.content_id = cc.content_id
        ) as progress
    into #nodes
    from sdocs_mfr_contents c
    where c.content_id in (select content_id from #gantt);

	create table #result(
		uid int identity primary key,
        -- tree
		node_id int,
		parent_id int,
		has_childs bit not null default(0),
		name varchar(500),
		node hierarchyid,
		-- attributes
		opers_from date,
		opers_to date,
		opers_days float,
		duration_buffer int,
		progress float,
		)

	insert into #result(node, parent_id, node_id, has_childs, name, opers_from, opers_to, opers_days, duration_buffer, progress)
	select 
		node,
		parent_id,
		child_id,
		has_childs,
		name,
		d_from, 
        d_to, 
        datediff(day, d_from, d_to),
		duration_buffer,
		isnull(progress, 0)
	from #nodes
	
	declare @today datetime = dbo.today()

    if @view_id is null or @view_id <> 10
        select
            x.node_id as 'id',
            x.name as 'text',
            opers_path = '',
            coalesce(x.opers_from, @today) as 'start_date',
            coalesce(x.opers_to, @today + 1) as 'end_date',
            x.opers_days as 'duration',
            x.duration_buffer,
            x.progress,
            cast(row_number() over (order by x.node) as float) as 'sortorder',
            x.parent_id as 'parent',
            'task' as 'type',
            isnull(x.has_childs, 0) as 'open',
            cast(case when x.duration_buffer = 0 then 1 else 0 end as bit) as 'is_critical'
        from #result x
        order by x.node.GetLevel(), x.opers_from, x.opers_to
    
    else
    begin
        create table #tasks (
            Id int identity primary key,
            Name varchar(max),
            Summary int,
            Critical bit,
            Start datetime,
            Finish datetime,
            ActualDuration varchar(20),
            Duration varchar(20),
            RemainingDuration varchar(20),
            OutlineLevel int
            )
        insert into #tasks(
            Name, Summary, Critical, [Start], Finish, ActualDuration, Duration, RemainingDuration, OutlineLevel
            )
        select 
            name, has_childs,
            case when duration_buffer = 0 then 1 else 0 end,
            opers_from, opers_to, 
            concat('PT', opers_days * 8, 'H'),
            concat('PT', opers_days * 8, 'H'),
            concat('PT', case when progress >= 1 then 0 else opers_days end * 8, 'H'),
            case when has_childs = 1 then 1 else 2 end
        from #result
        order by node

        declare @result_xml xml = (
            select *
            from (
                select 			
                    14 as 'SaveVersion',
                    concat('Операции заказа #', @doc_id) as 'Title',
                    (select min(Start) from #tasks) as 'StartDate',
                    (
                        select * from #tasks Task order by Id
                        for xml auto, type, elements
                    ) Tasks
                ) Project
            for xml auto, type, elements
            )

        set @result_xml = replace(cast(@result_xml as varchar(max)), '<Project>', '<Project xmlns="http://schemas.microsoft.com/project">')
        select @result_xml
    end
	exec drop_temp_table '#nodes,#result'
end
go

-- exec mfr_items_view_gantt 651733, 26061, @view_id = 10 -- CЭЗ