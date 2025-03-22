if object_id('prodmeta_classes_view') is not null drop proc prodmeta_classes_view
go
-- exec prodmeta_classes_view
create proc prodmeta_classes_view
	@parent_id int = null,
	@search varchar(max) = null
as
begin
	set @search = '%' + @search + '%';

	declare @result table (class_id int primary key, node hierarchyid);

	if @parent_id is not null
		insert into @result(class_id)
		select class_id
		from prodmeta_classes
		where parent_id = @parent_id;
	
	else begin
		if @search is not null 
			insert into @result(class_id, node)
			select a.class_id, a.node
			from prodmeta_classes a
			where (
				a.name like @search
				or a.note like @search
				);

		else begin
			insert into @result(class_id, node)
			select a.class_id, a.node
			from prodmeta_classes a
			where a.is_deleted = 0;
		end

		insert into @result(class_id, node)
		select distinct x.class_id, x.node
		from prodmeta_classes x
			join @result r on r.node.IsDescendantOf(x.node) = 1
		where x.has_childs = 1
			and x.is_deleted = 0
			and not exists(select 1 from @result where class_id = x.class_id);
	end

-- select
	select x.*
	from @result r
		join prodmeta_classes x on x.class_id = r.class_id
	order by x.node;

end
GO
