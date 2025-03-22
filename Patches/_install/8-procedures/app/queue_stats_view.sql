if object_id('queue_stats_view') is not null drop proc queue_stats_view
go
create proc queue_stats_view
    @dbnames varchar(1000),
	@search nvarchar(1000) = null
as
begin
    set nocount on;

		set @search = '%' + coalesce(@search, '') + '%'

		declare @db_search table(dbname varchar(30))
		declare @db_names table(dbname varchar(30))
		if @dbnames is not null insert into @db_search select item from dbo.str2rows(@dbnames, ',')

		insert into @db_names
			select name from CISP_SHARED..APP_DATABASES adb
				join @db_search dbs on 
					adb.NAME like ('%' + dbs.dbname  + '%')

    -- время выполнения (по-умолчанию) - QueueDurations
        declare @lags table(lag_from int, lag_to int);
        insert into @lags values (0, 3), (3, 5), (5, 10), (10, 30), (30, 60);

        select
            QueueDurations = dbo.xml2json((
                select
                    row_number() over (order by count(0)) as row_id,
                    lag_group = concat(l.lag_from, '..', l.lag_to, '(s)'),
                    lag = avg(lag),
                    duration = cast(avg(dur) as decimal(5,2)),
                    qty = count(*)
                from (
                    select *,
                        lag = datediff(second, add_date, process_start),
                        dur = process_duration/1000.
                    from queues 
                    where priority_id = 0
                    ) q
                    join @lags l on q.lag >= l.lag_from and q.lag < l.lag_to
                where dbname in (select dbname from @db_names)
					and (group_name like @search
						or name like @search
						or sql_cmd like @search
					)
				and add_date >= dbo.today() 
                group by concat(l.lag_from, '..', l.lag_to, '(s)')
                order by min(l.lag_from)
                for xml raw
            )),

    -- длинные запросы - QueueLongs
            QueueLongs = dbo.xml2json((
                select top 20
                    (row_number() over (order by name)) as row_id,
                    process_duration,
                    name as long_query,
                    process_start,
                    datediff(second, add_date, process_start) as lag,
                    duration = cast(process_duration/1000. as decimal(5,2))
                from queues 
                where dbname in (select dbname from @db_names)
					and (group_name like @search
						or name like @search
						or sql_cmd like @search
						)
                    and add_date >= dbo.today() 
                    and process_duration > 5000
                    and priority_id = 0
                order by process_duration desc
                for xml raw
            )),

    -- загрузка по часам - QueueHoursDistrib
            QueueHoursDistrib = dbo.xml2json((
                select 
					row_number() over (order by hour) as row_id,
					*
				from (
					select
						datepart(hour, add_date) as hour, 
						count( * ) as queues_count
					from queues 
					where dbname in (select dbname from @db_names)
						and (group_name like @search
							or name like @search
							or sql_cmd like @search
						)
					and add_date >= dbo.today() 
					group by datepart(hour, add_date)
				) x
				order by hour
                for xml raw
            )),

    -- хиты запросов - QueueHits
            QueueHits = dbo.xml2json((
                select 
                    (row_number() over (order by name)) as row_id,
                    dbname, 
                    name, 
                    count(*) as queues_count 
                from queues 
                where dbname in (select dbname from @db_names)
					and (group_name like @search
						or name like @search
						or sql_cmd like @search
						)
					and add_date >= dbo.today() 
                group by dbname, name
                order by dbname, count(*) desc
                for xml raw
            )),

    -- статистика вызова отчётов - ReportsHits
            ReportsHits = dbo.xml2json((
                select 
                    (row_number() over (order by template_name)) as row_id,
                    template_name, c_calls = count(*), c_mols = count(distinct mol_id),
                    avg_time_sec = cast(avg(datediff(ms, process_start, process_end)) / 1000. as decimal(15,2)),
                    max_date = max(process_start)
                from reports_log
				where template_name like @search
                group by template_name
                having max(process_start) >= dateadd(d, -14, getdate())
                order by 4 desc
                for xml raw
            ))

end
go
-- exec queue_stats_view 'CISP_VMZ'