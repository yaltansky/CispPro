if object_id('mfr_route_check') is not null drop proc mfr_route_check
go
create proc mfr_route_check
	@route_id int
as
begin

	set nocount on;

BEGIN TRY
BEGIN TRANSACTION

	if exists(select 1 from mfr_routes_details where route_id = @route_id and place_id is null)
		raiserror('Необходимо указать участок для операции.', 16, 1)

	-- удалить с пустой длительностью
	delete from mfr_routes_details where route_id = @route_id and isnull(duration,0) = 0
	
	-- обнулить ссылки на себя
	update mfr_routes_details set predecessors = null where route_id = @route_id and try_cast(predecessors as int) = number

	declare @predecessors varchar(100), @is_first bit

	update x
	set @predecessors = replace(replace(x.predecessors, ' ', ';'), ',', ';'),
		@is_first = case when l.prev_id is null or isnull(@predecessors,'') = '' then 1 end,
		predecessors = isnull(predecessors, @predecessors),
		is_first = @is_first,
		is_last = case when l.next_id is null then 1 end
	from mfr_routes_details x
		join (
			select 
				id,
				prev_id = lag(id, 1, null) over (partition by route_id order by number),
				next_id = lead(id, 1, null) over (partition by route_id order by number)
			from mfr_routes_details
			where route_id = @route_id
		) l on l.id = x.id

	-- if exists(
	-- 	select 1 from mfr_routes_details x 
	-- 		cross apply dbo.str2rows(predecessors, ';') pr
	-- 	where route_id = @route_id 
	-- 		and predecessors is not null
	-- 		and not exists(
	-- 			select 1 from mfr_routes_details
	-- 			where route_id = x.route_id
	-- 				and number = try_cast(pr.item as int))
	-- 	)
	-- 	raiserror('Неверно указан предшественник операции.', 16, 1)

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH -- TRANSACTION

end
GO
