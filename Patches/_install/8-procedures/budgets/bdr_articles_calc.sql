if object_id('bdr_articles_calc') is not null drop proc bdr_articles_calc
go
create proc bdr_articles_calc
	@mode_id int = 4,
	@ids varchar(max) = null
as
begin

	set nocount on;

	-- 1 - принять к учёту, 2 - в черновик
	if @mode_id in (1,2)
	begin
		declare @rows table(article_id int)
		insert into @rows select distinct item from dbo.str2rows(@ids,',')

		update x
		set status_id = case when @mode_id = 1 then 1 else 0 end
		from bdr_articles x
		where x.has_childs = 0
			and x.article_id in (select article_id from @rows)

		-- status_id
		update x
		set status_id = 
				case
					when exists(select 1 from bdr_articles where node <> x.node and node.IsDescendantOf(x.node) = 1 and has_childs = 0 and status_id = 0) then 0
					else 1
				end
		from bdr_articles x
		where has_childs = 1
	end

	-- calc mapping
	else if @mode_id = 3
	begin
		update x
		set article_id = a.main_id
		from findocs x
			inner join bdr_articles a on a.article_id = x.article_id
		where a.main_id is not null

		update x
		set article_id = a.main_id
		from findocs_details x
			inner join bdr_articles a on a.article_id = x.article_id
		where a.main_id is not null	
	end

	-- hierarchyid
	else if @mode_id = 4
	begin
		---- delete marked as deleted
		--delete from bdr_articles where is_deleted = 1

		-- update fake parents
		update x
		set parent_id = null
		from bdr_articles x
		where parent_id is not null
			and not exists(select 1 from bdr_articles where article_id = x.parent_id)

		-- recalc
		exec tree_calc_nodes 'bdr_articles', 'article_id', @use_sort_id = 1
	end

end
GO
