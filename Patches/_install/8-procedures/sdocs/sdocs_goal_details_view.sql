if object_id('sdocs_goal_details_view') is not null drop procedure sdocs_goal_details_view
go
create proc sdocs_goal_details_view
	@mol_id int,
	@goal_id int,
	@group_id varchar(32),
	@node_id int,
	@search varchar(50) = null
as
begin
	
	set nocount on;
	
	declare @node hierarchyid = (select top 1 node from sdocs_goals_sums 
		where goal_id = @goal_id
			and mol_id = @mol_id
			and group_id = @group_id
			and node_id = @node_id
		)

	select 
		NODE_ID = CASE WHEN XD.PRODUCT_ID IS NULL THEN CAST(X.NODE_ID AS VARCHAR) ELSE CONCAT('D', XD.ID_ORDER, 'P', XD.PRODUCT_ID) END,
		PARENT_ID = CASE WHEN X.NODE_ID <> @NODE_ID THEN X.PARENT_ID END,
		X.HAS_CHILDS,
		X.NAME,
		STOCK.NAME AS STOCK_NAME,
		P.NAME AS PRODUCT_NAME,
		XD.ID_ORDER,
		XD.STOCK_ID,
		XD.PRODUCT_ID,
		XD.Q_ORDER,
		XD.V_ORDER,
		XD.Q_MFR,
		XD.Q_ISSUE,
		XD.Q_SHIP,
		x.NODE
	into #result
	from sdocs_goals_sums x
		left join sdocs_goals_details xd on xd.id_order = x.id_order
			left join products p on p.product_id = xd.product_id
			left join sdocs_stocks stock on stock.stock_id = xd.stock_id
	where x.goal_id = @goal_id
		and x.mol_id = @mol_id
		and x.group_id = @group_id
		and x.node.IsDescendantOf(@node) = 1

	update x
	set q_order = r.q_order,
		v_order = r.v_order,
		q_mfr = r.q_mfr,
		q_issue = r.q_issue,
		q_ship = r.q_ship
	from #result x
		join (
			select y2.node_id, 
				sum(y1.q_order) as q_order,
				sum(y1.v_order) as v_order,
				sum(y1.q_mfr) as q_mfr,
				sum(y1.q_issue) as q_issue,
				sum(y1.q_ship) as q_ship
			from #result y1
				cross apply #result y2
			where (y2.has_childs = 1 and y1.has_childs = 0)
				and y1.node.IsDescendantOf(y2.node) = 1
			group by y2.node_id
		) r on r.node_id = x.node_id

	select * from #result order by node, product_name
	drop table #result
end
go