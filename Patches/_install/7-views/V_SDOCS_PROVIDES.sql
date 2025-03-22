IF OBJECT_ID('V_SDOCS_PROVIDES') IS NOT NULL DROP VIEW V_SDOCS_PROVIDES
GO
CREATE VIEW V_SDOCS_PROVIDES
as

select
	STATUS_NAME = XS.NAME,
	DEAL_NUMBER = ORD.DEAL_NUMBER,
	DEAL_AGENT_NAME = A.NAME,
	MFR_NUMBER = MFR.NUMBER,
	ISSUE_NUMBER = ISSUE.NUMBER,
	SHIP_NUMBER = SHIP.NUMBER,
	ORDER_NUMBER = ORD.NUMBER,
	STOCK_NAME = STOCK.NAME,
	PRODUCT_NAME = P.NAME,
	X.Q_ORDER,
	X.Q_MFR,
	X.Q_ISSUE,
	X.Q_SHIP,
	X.V_MFR,
	X.V_ORDER,
	X.V_PAID,
	X.D_ORDER,
	X.D_DELIVERY,
	X.D_MFR,
	X.D_ISSUE_PLAN,
	X.D_ISSUE,
	X.D_SHIP,
	X.STOCK_ID,
	X.PRODUCT_ID,
	X.SLICE,
	X.NOTE,
	ID_ORDER,
	ID_MFR,
	ID_ISSUE,
	ID_SHIP,
	ID_DEAL,
	HID_ORDER = concat('#', X.ID_ORDER),
	HID_MFR = concat('#', X.ID_MFR),
	HID_ISSUE = concat('#', X.ID_ISSUE),
	HID_SHIP = concat('#', X.ID_SHIP),
	HID_DEAL = concat('#', X.ID_DEAL)
from sdocs_provides x
	left join sdocs_provides_statuses xs on xs.status_id = x.status_id
	left join sdocs mfr on mfr.doc_id = x.id_mfr
	left join sdocs issue on issue.doc_id = x.id_issue
	left join sdocs ship on ship.doc_id = x.id_ship
	left join sdocs ord on ord.doc_id = x.id_order
		left join agents a on a.agent_id = ord.agent_id
	left join sdocs_stocks stock on stock.stock_id = x.stock_id
	left join products p on p.product_id = x.product_id

GO
