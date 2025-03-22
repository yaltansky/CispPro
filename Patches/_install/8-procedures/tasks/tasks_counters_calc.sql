if object_id('tasks_counters_calc') is not null drop proc tasks_counters_calc
go
create proc tasks_counters_calc
as
begin

	set nocount on;

	declare @today datetime = dbo.today()
	declare @result table(counter_id int, mol_id int, task_id int, is_normal int, is_over int, counts_risks int)

-- авто-закрытие задач
	update x
	set status_id = 5
	from tasks x
		inner join (
			select task_id, max(d_add) as last_d_add
			from tasks_hists
			group by task_id
		) h on h.task_id = x.task_id
	where x.status_id = 4
		and datediff(d, h.last_d_add, @today) > 10

-- Заказчики
	insert into @result(counter_id, mol_id, task_id, is_over, counts_risks)
	select 1,
		x.author_id,
		x.task_id,
		case when x.d_deadline < @today then 1 else 0 end,
		datediff(d, h.last_d_add, @today) * 3
	from tasks x
		inner join (
			select task_id, mol_id, max(d_add) as last_d_add
			from tasks_hists
			group by task_id, mol_id
		) h on h.task_id = x.task_id and h.mol_id = x.analyzer_id
	where x.owner_id = x.author_id
		and x.status_id not in (-1,5)

-- Координаторы
	insert into @result(counter_id, mol_id, task_id, is_over, counts_risks)
	select 2, 
		x.analyzer_id,
		x.task_id,
		case when x.d_deadline < @today then 1 else 0 end,
		datediff(d, h.last_d_add, @today) * 3
	from tasks x
		inner join (
			select task_id, max(d_add) as last_d_add
			from tasks_hists
			group by task_id
		) h on h.task_id = x.task_id
	where x.owner_id = x.analyzer_id
		and x.status_id not in (-1,5)

-- Исполнители
	insert into @result(counter_id, mol_id, task_id, is_over, counts_risks)
	select 3, 
		x.mol_id,
		x.task_id,
		case when x.d_deadline < @today then 1 else 0 end,
		datediff(d, x.add_date, @today) +
		isnull(datediff(d, x.d_deadline, @today) * 5, 0)
	from tasks_mols x
		inner join tasks t on t.task_id = x.task_id
	where t.status_id = 2
		and x.role_id = 1
		and x.d_executed is null

	update @result set is_normal = 1 where is_over = 0

-- Уведомления
	create table #counts_alerts(mol_id int, count_reads int, count_unreads int)
	insert into #counts_alerts exec events_get_groups;20
	delete from #counts_alerts where mol_id = -25
	
	insert into @result(counter_id, mol_id, task_id, is_normal, is_over, counts_risks)
	select 4, mol_id, mol_id, count_reads, 0, 1 from #counts_alerts where count_reads > 0
	union select 4, mol_id, mol_id, 0, count_unreads, count_unreads from #counts_alerts where count_unreads > 0

-- results by tasks
	truncate table tasks_counters_details;
	delete from @result where isnull(counts_risks,0) = 0
	delete from @result where mol_id not in (select mol_id from mols where is_working = 1)

	insert into tasks_counters_details(counter_id, mol_id, task_id, is_over, counts_risks)
	select counter_id, mol_id, task_id, is_over, counts_risks
	from @result

-- results by mols
	truncate table tasks_counters;
	insert into tasks_counters(name, has_childs) values ('Заказчики', 1), ('Координаторы', 1), ('Исполнители', 1), ('Уведомления', 1)

	insert into tasks_counters(parent_id, name, mol_id, counts, counts_over, counts_risks)
	select counter_id, name, mol_id, counts, counts_over, counts_risks
	from (
		select 
			r.counter_id, mols.name, mols.mol_id,
			sum(is_normal) as counts,
			sum(is_over) as counts_over,
			sum(counts_risks) as counts_risks,
			row_number() over (partition by r.counter_id order by sum(counts_risks) desc) as row_id
		from @result r
			inner join mols on mols.mol_id = r.mol_id
		where counts_risks > 0
			and mols.is_working = 1
		group by r.counter_id, mols.name, mols.mol_id
		) u
	where u.row_id <= 30
	order by counter_id, counts_risks desc

	update x
	set counts =
			case
				when x.node_id < 4 then (select count(distinct task_id) from @result where counter_id = x.node_id)
				else (select sum(is_normal) from @result where counter_id = x.node_id)
			end,
		counts_over = 
			case
				when x.node_id < 4 then (select count(distinct task_id) from @result where counter_id = x.node_id and is_over = 1)
				else (select sum(is_over) from @result where counter_id = x.node_id)
			end
	from tasks_counters x
	where x.parent_id is null

end
GO
