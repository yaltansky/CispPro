if object_id('bdr_articles_search') is not null
	drop proc bdr_articles_search
go
create proc bdr_articles_search
	@search varchar(250) = null,
	@status_id int = null,
	@hide_mapping bit = 0
as
begin

	set nocount on;

	declare @result table (article_id int, node hierarchyid)

	if @search is null and @status_id is null
	begin
		insert into @result
			select article_id, node
			from bdr_articles
			where parent_id is null
	end
	
	else begin
		declare @id int

		if dbo.hashid(@search) is not null
		begin
			set @id = dbo.hashid(@search)
			set @search = null
		end

		set @search = '%' + replace(@search, ' ', '%') + '%'

		insert into @result
			select article_id, node
			from bdr_articles
			where (@id is null or article_id = @id)
				and (@search is null or name like @search)
				and (@status_id is null 
					or (
						(@status_id <> 1 and status_id = @status_id)
						or (status_id = 1 and main_id is null and has_childs = 0) -- показывать только главные статьи
					)					
				)						
				and (@hide_mapping = 0 or (main_id is null))
				and is_deleted = 0

		-- get all parents
		insert into @result(article_id, node)
			select distinct x.article_id, x.node
			from bdr_articles x
				inner join @result r on r.node.IsDescendantOf(x.node) = 1
			where x.has_childs = 1
				and x.is_deleted = 0
	end

	select
		x.ARTICLE_ID,
		x.NODE_ID,
		x.NAME,
		x.SHORT_NAME,
		x.SUBJECT_ID,
		x.DIRECTION,
		x.IS_SOURCE,
		x.MAIN_ID,
		MAIN_NAME = xm.NAME,
		x.STATUS_ID,
		STATUS_NAME = xs.NAME,
		x.PARENT_ID,
		x.HAS_CHILDS,
		x.LEVEL_ID,
		x.SORT_ID,
		x.IS_DELETED
	from bdr_articles x
		inner join bdr_articles_statuses xs on xs.status_id = x.status_id
		left join bdr_articles xm on xm.article_id = x.main_id
	where x.article_id in (select article_id from @result)
		and x.is_deleted = 0
	order by x.node
end
GO
