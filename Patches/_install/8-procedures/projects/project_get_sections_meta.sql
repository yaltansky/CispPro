if object_id('project_get_sections_meta') is not null
	drop proc project_get_sections_meta
GO

create proc project_get_sections_meta
	@project_id int,
	@tree_id int
as
begin

	set nocount on;

	declare @access table(project_id int, node hierarchyid, inherited_access bit, section_id int, a_read tinyint, a_update tinyint)
	declare @result table(section_id int primary key, a_read tinyint, a_update tinyint)

-- get @tree_id
	insert into @access(project_id, node, inherited_access, section_id, a_read, a_update)
		select m.project_id, m.node, m.inherited_access, s.section_id, s.is_required, 0
		from projects_mols m, projects_sections s
		where m.project_id = @project_id
			and m.id = @tree_id

-- get self access
	insert into @access(project_id, node, inherited_access, section_id, a_read, a_update)
		select m.project_id, m.node, m.inherited_access, s.section_id, s.a_read, s.a_update
		from projects_mols m
			inner join projects_mols_sections_meta s on s.project_id = m.project_id and s.tree_id = m.id
		where m.project_id = @project_id
			and m.id = @tree_id
		order by m.id, s.section_id

	declare @node hierarchyid, @inherited_access bit
	select @node = node, @inherited_access = inherited_access from projects_mols where id = @tree_id

-- + inherits from parents
	insert into @access(section_id, a_read, a_update)
		select s.section_id, s.a_read, s.a_update
		from @access a
			inner join projects_mols m on m.project_id = a.project_id and a.node.IsDescendantOf(m.node) = 1
			inner join projects_mols_sections_meta s on s.project_id = m.project_id and s.tree_id = m.id			
		where m.project_id = @project_id
			and a.inherited_access = 1

-- result access
	insert into @result(section_id, a_read, a_update)
	select 
		section_id,
		max(a_read) as a_read,
		max(a_update) as a_update
	from @access
	group by section_id

	select 
		S.SECTION_ID,
		S.NAME,
		S.CSS, S.CSS_LI, S.IS_DEFAULT, S.IS_REQUIRED,
		R.A_READ,
		R.A_UPDATE
	from projects_sections s
		inner join @result r on r.section_id = s.section_id
	order by s.sort_id

end
GO
